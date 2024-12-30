// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract TokenWrapper is ERC20Permit, Ownable, ReentrancyGuard {
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
    ) ERC20(_name, _symbol) ERC20Permit(_name) Ownable(msg.sender) {
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

    // Original rate limiting functions remain the same
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

    // New permit wrap function
    function wrapWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        require(amount > 0, "TokenWrapper: Zero amount");
        require(amount <= MAX_UNDERLYING_BALANCE, "TokenWrapper: Amount exceeds maximum");
        
        // Execute permit on underlying token if it supports EIP-2612
        if (address(underlyingToken).code.length > 0) {
            try IERC20Permit(address(underlyingToken)).permit(
                msg.sender,
                address(this),
                amount,
                deadline,
                v,
                r,
                s
            ) {} catch {
                // Silently fail if permit is not supported
            }
        }

        // Proceed with normal wrap
        _checkAndUpdateRateLimit(amount, true);

        uint256 initialBalance = balanceOf(msg.sender);
        uint256 initialUnderlyingBalance = underlyingToken.balanceOf(address(this));
        
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 receivedAmount = underlyingToken.balanceOf(address(this)) - initialUnderlyingBalance;
        require(receivedAmount == amount, "TokenWrapper: Transfer amount mismatch");
        
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

    // Original wrap function remains the same
    function wrap(uint256 amount) external nonReentrant {
        // ... existing wrap implementation ...
    }

    // Original unwrap function remains the same
    function unwrap(uint256 amount) external nonReentrant {
        // ... existing unwrap implementation ...
    }

    // Original helper functions remain the same
    function setRateLimits(uint256 _maxWrapPerWindow, uint256 _maxUnwrapPerWindow) external onlyOwner {
        // ... existing implementation ...
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

    // Events remain the same
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
