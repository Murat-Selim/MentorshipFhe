// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint32, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract Mentorship is ZamaEthereumConfig {
    struct Mentor {
        address mentor;
        euint32 meetLink; // ciphertext handle
        uint256 price;
        uint256 version;
    }

    struct Request {
        address mentor;
        address user;
        uint256 price;
        uint256 expiry;
        bool fulfilled;
        bytes32 cipherHandle; // stored ciphertext handle for reference
    }

    mapping(address => Mentor) public mentors; // mentorAddr -> Mentor
    mapping(address => mapping(address => bool)) public accepted; // accepted[mentor][user]
    mapping(uint256 => Request) public requests; // requestId -> Request
    mapping(address => mapping(address => uint256)) private userMeetLinks; // decrypted cleartext stored (note: on-chain state is public)
    mapping(address => uint256) public nonces; // user nonces for uniqueness
    mapping(address => uint256) public balances; // escrowed USDC balances for mentors

    address public usdc;
    address public owner;

    // reentrancy guard
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    event MentorshipAdded(address indexed mentor, uint256 price, uint256 version);
    event UserAccepted(address indexed mentor, address indexed user, uint256 requestId);
    event LinkSubmitted(uint256 indexed requestId, address indexed submitter);
    event LinkDecryptedOnChain(address indexed mentor, address indexed user);
    event RefundProcessed(address indexed mentor, address indexed user, uint256 requestId);
    event MentorWithdraw(address indexed mentor, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrant");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    constructor(address _usdc) {
        owner = msg.sender;
        usdc = _usdc;
        _status = _NOT_ENTERED;
    }

    // Owner can change USDC token if needed
    function setUSDC(address _usdc) external onlyOwner {
        usdc = _usdc;
    }

    // meetLinkCipher: the ciphertext handle (bytes32) returned/used by Zama libs
    function addMentorship(externalEuint32 meetLinkCipher, bytes calldata proof, uint256 price) external {
        require(price > 0, "Price must be positive");
        Mentor storage m = mentors[msg.sender];
        m.mentor = msg.sender;
        m.meetLink = FHE.fromExternal(meetLinkCipher, proof);
        m.price = price;
        m.version += 1;
        // allowThis grants permission for this ciphertext to be used according to Zama API
        FHE.allowThis(m.meetLink);
        emit MentorshipAdded(msg.sender, price, m.version);
    }

    // User joins mentorship: pay into contract escrow and create a request that an off-chain relayer will satisfy
    function joinMentorship(address mentor) external nonReentrant {
        Mentor storage m = mentors[mentor];
        require(m.price > 0, "Mentor not found");
        require(!accepted[mentor][msg.sender], "Already accepted");

        // transfer tokens from user into contract escrow
        bool ok = IERC20(usdc).transferFrom(msg.sender, address(this), m.price);
        require(ok, "Payment failed");

        // mark accepted (prevents double joining)
        accepted[mentor][msg.sender] = true;

        // create unique request id
        uint256 nonce = nonces[msg.sender]++;
        uint256 requestId = uint256(keccak256(abi.encodePacked(mentor, msg.sender, nonce, block.timestamp)));

        // store request; give oracle/relayer some time (e.g., 1 hour) to submit decrypted result
        bytes32 handle = FHE.toBytes32(m.meetLink);
        requests[requestId] = Request({
            mentor: mentor,
            user: msg.sender,
            price: m.price,
            expiry: block.timestamp + 1 hours,
            fulfilled: false,
            cipherHandle: handle
        });

        // track escrow for mentor (withdrawable once mentor chooses to withdraw)
        balances[mentor] += m.price;

        emit UserAccepted(mentor, msg.sender, requestId);
    }

    // Off-chain relayer or the user (whoever performed decrypt) calls this to submit cleartext + proof.
    function submitDecryptedLink(
        uint256 requestId,
        bytes calldata cleartexts, // abi.encode(uint256 link)
        bytes calldata proof
    ) external nonReentrant {
        Request storage r = requests[requestId];
        require(r.user != address(0), "Unknown request");
        require(!r.fulfilled, "Already fulfilled");
        require(block.timestamp <= r.expiry, "Request expired");

        // Prepare handles list for verification
        bytes32[] memory handlesList = new bytes32[](1);
        handlesList[0] = r.cipherHandle;

        // Verify the decryption proof
        FHE.checkSignatures(handlesList, cleartexts, proof);

        // decode cleartext (we expect a uint256 link)
        uint256 link = abi.decode(cleartexts, (uint256));

        // store link on-chain for the specific mentor/user pair
        userMeetLinks[r.mentor][r.user] = link;

        r.fulfilled = true;

        emit LinkSubmitted(requestId, msg.sender);
        emit LinkDecryptedOnChain(r.mentor, r.user);
    }

    // Mentor withdraws their escrowed balance (we don't force per-request holds here; mentors can withdraw aggregated balance)
    function withdrawForMentor() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");
        balances[msg.sender] = 0;
        bool ok = IERC20(usdc).transfer(msg.sender, amount);
        require(ok, "Withdraw failed");
        emit MentorWithdraw(msg.sender, amount);
    }

    // Refund if relayer/off-chain decrypt did not arrive in time
    function refund(uint256 requestId) external nonReentrant {
        Request storage r = requests[requestId];
        require(r.user == msg.sender, "Not requester");
        require(!r.fulfilled, "Already fulfilled");
        require(block.timestamp > r.expiry, "Not expired yet");

        // reset accepted flag so user may retry (or join another mentor)
        accepted[r.mentor][r.user] = false;

        // decrease mentor escrow balance and return to user
        require(balances[r.mentor] >= r.price, "Insufficient escrow");
        balances[r.mentor] -= r.price;

        // mark fulfilled to avoid re-entrance
        r.fulfilled = true;

        bool ok = IERC20(usdc).transfer(r.user, r.price);
        require(ok, "Refund transfer failed");

        emit RefundProcessed(r.mentor, r.user, requestId);
    }

    // Getter for the link (user only)
    function getMeetLink(address mentor) external view returns (uint256) {
        require(accepted[mentor][msg.sender], "Not accepted");
        uint256 link = userMeetLinks[mentor][msg.sender];
        require(link != 0, "Link not available yet");
        return link;
    }

    function isAccepted(address mentor, address user) external view returns (bool) {
        return accepted[mentor][user];
    }

    function getMentor(address mentor) external view returns (address, uint256, uint256) {
        Mentor memory m = mentors[mentor];
        return (m.mentor, m.price, m.version);
    }
}

