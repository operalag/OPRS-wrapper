// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenWrapper is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlyingToken;
    uint8 private immutable underlyingDecimals;
    uint256 private immutable scalingFactor;
    
    // Flash loan protection parameters
    uint256 public constant WINDOW_SIZE = 1 hours;
    uint256 public maxWrapPerWindow;
    uint256 public maxUnwrapPerWindow;
    uint256 public constant MAX_UNDERLYING_BALANCE = type(uint96).max;
    
    // Volume tracking
    mapping(uint256 => uint256) public wrapVolume;
    mapping(uint256 => uint256) public unwrapVolume;

    constructor(
        address _underlyingToken,
        string memory _name,
        string memory _symbol,
        uint256 _maxWrapPerWindow,
        uint256 _maxUnwrapPerWindow
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_underlyingToken != address(0), "TokenWrapper: Zero address");
        require(bytes(_name).length > 0, "TokenWrapper: Empty name");
        require(bytes(_symbol).length > 0, "TokenWrapper: Empty symbol");
        require(_maxWrapPerWindow > 0, "TokenWrapper: Invalid wrap limit");
        require(_maxUnwrapPerWindow > 0, "TokenWrapper: Invalid unwrap limit");
        
        underlyingToken = IERC20(_underlyingToken);
        
        try ERC20(_underlyingToken).decimals() returns (uint8 decimals) {
            underlyingDecimals = decimals;
        } catch {
            revert("TokenWrapper: Invalid token interface");
        }
        
        require(underlyingDecimals <= 18, "TokenWrapper: Decimals too high");
        scalingFactor = 10 ** (18 - underlyingDecimals);
        
        maxWrapPerWindow = _maxWrapPerWindow;
        maxUnwrapPerWindow = _maxUnwrapPerWindow;
    }

    function getCurrentWindow() public view returns (uint256) {
        return block.timestamp / WINDOW_SIZE;
    }

    function getWindowVolume(uint256 window, bool isWrap) public view returns (uint256) {
        return isWrap ? wrapVolume[window] : unwrapVolume[window];
    }

    function _checkAndUpdateRateLimit(uint256 amount, bool isWrap) internal {
        uint256 currentWindow = getCurrentWindow();
        uint256 currentVolume = getWindowVolume(currentWindow, isWrap);
        uint256 maxAmount = isWrap ? maxWrapPerWindow : maxUnwrapPerWindow;
        
        require(
            currentVolume + amount <= maxAmount,
            "TokenWrapper: Rate limit exceeded"
        );
        
        if(isWrap) {
            wrapVolume[currentWindow] += amount;
        } else {
            unwrapVolume[currentWindow] += amount;
        }
    }

    function wrap(uint256 amount) external nonReentrant {
        require(amount > 0, "TokenWrapper: Zero amount");
        require(amount <= MAX_UNDERLYING_BALANCE, "TokenWrapper: Amount exceeds maximum");
        
        // Check rate limit
        _checkAndUpdateRateLimit(amount, true);

        // Cache balances
        uint256 initialBalance = balanceOf(msg.sender);
        uint256 initialUnderlyingBalance = underlyingToken.balanceOf(address(this));
        
        // Transfer underlying tokens
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Verify transfer
        uint256 receivedAmount = underlyingToken.balanceOf(address(this)) - initialUnderlyingBalance;
        require(receivedAmount == amount, "TokenWrapper: Transfer amount mismatch");
        
        // Mint wrapped tokens
        uint256 wrappedAmount = amount * scalingFactor;
        _mint(msg.sender, wrappedAmount);
        
        emit Wrapped(
            msg.sender,
            amount,
            wrappedAmount,
            initialBalance,
            balanceOf(msg.sender),
            initialUnderlyingBalance,
            underlyingToken.balanceOf(address(this))
        );
    }

    function unwrap(uint256 amount) external nonReentrant {
        require(amount > 0, "TokenWrapper: Zero amount");
        require(amount % scalingFactor == 0, "TokenWrapper: Invalid amount");
        
        uint256 underlyingAmount = amount / scalingFactor;
        
        // Check rate limit
        _checkAndUpdateRateLimit(underlyingAmount, false);
        
        // Cache balances
        uint256 initialBalance = balanceOf(msg.sender);
        uint256 initialUnderlyingBalance = underlyingToken.balanceOf(address(this));
        
        require(
            underlyingAmount <= underlyingToken.balanceOf(address(this)),
            "TokenWrapper: Insufficient underlying balance"
        );
        
        // Burn wrapped tokens
        _burn(msg.sender, amount);
        
        // Transfer underlying tokens
        underlyingToken.safeTransfer(msg.sender, underlyingAmount);
        
        emit Unwrapped(
            msg.sender,
            amount,
            underlyingAmount,
            initialBalance,
            balanceOf(msg.sender),
            initialUnderlyingBalance,
            underlyingToken.balanceOf(address(this))
        );
    }

    function setRateLimits(
        uint256 _maxWrapPerWindow,
        uint256 _maxUnwrapPerWindow
    ) external onlyOwner {
        require(_maxWrapPerWindow > 0, "TokenWrapper: Invalid wrap limit");
        require(_maxUnwrapPerWindow > 0, "TokenWrapper: Invalid unwrap limit");
        maxWrapPerWindow = _maxWrapPerWindow;
        maxUnwrapPerWindow = _maxUnwrapPerWindow;
        emit RateLimitsUpdated(_maxWrapPerWindow, _maxUnwrapPerWindow);
    }

    function getUnderlyingAmount(uint256 wrappedAmount) public view returns (uint256) {
        return wrappedAmount / scalingFactor;
    }

    function getWrappedAmount(uint256 underlyingAmount) public view returns (uint256) {
        return underlyingAmount * scalingFactor;
    }

    function getUnderlyingDecimals() external view returns (uint8) {
        return underlyingDecimals;
    }

    // Events
    event Wrapped(
        address indexed user,
        uint256 underlyingAmount,
        uint256 wrappedAmount,
        uint256 previousBalance,
        uint256 newBalance,
        uint256 previousUnderlyingBalance,
        uint256 newUnderlyingBalance
    );

    event Unwrapped(
        address indexed user,
        uint256 wrappedAmount,
        uint256 underlyingAmount,
        uint256 previousBalance,
        uint256 newBalance,
        uint256 previousUnderlyingBalance,
        uint256 newUnderlyingBalance
    );

    event RateLimitsUpdated(uint256 maxWrapPerWindow, uint256 maxUnwrapPerWindow);
}
