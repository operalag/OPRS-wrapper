// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title SecureTokenWrapper
 * @notice A secure wrapper for ERC20 tokens with comprehensive security measures
 * @dev Implements EIP-2612 permit, flash loan protection, and extensive security validations
 */
contract SecureTokenWrapper is ERC20Permit, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlyingToken;
    uint8 private immutable underlyingDecimals;
    uint256 private immutable scalingFactor;
    
    // Security parameters
    uint256 public constant WINDOW_SIZE = 1 hours;
    uint256 public maxWrapPerWindow;
    uint256 public maxUnwrapPerWindow;
    uint256 public constant MAX_UNDERLYING_BALANCE = type(uint96).max;
    uint256 private constant MAX_SAFE_AMOUNT = type(uint96).max / (10 ** 18);
    
    // Sliding window implementation
    struct Operation {
        uint256 amount;
        uint256 timestamp;
    }
    
    mapping(address => Operation[]) private wrapOperations;
    mapping(address => Operation[]) private unwrapOperations;
    
    // Emergency controls
    bool public isEmergencyMode;
    
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
        require(_maxWrapPerWindow > 0 && _maxWrapPerWindow <= MAX_SAFE_AMOUNT, "TokenWrapper: Invalid wrap limit");
        require(_maxUnwrapPerWindow > 0 && _maxUnwrapPerWindow <= MAX_SAFE_AMOUNT, "TokenWrapper: Invalid unwrap limit");
        
        // Validate token interface and behavior
        require(_underlyingToken.code.length > 0, "TokenWrapper: Not a contract");
        _validateTokenImplementation(_underlyingToken);
        
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

    // Security validation functions
    function _validateTokenImplementation(address token) private view {
        // Basic ERC20 interface validation
        try ERC20(token).totalSupply() returns (uint256) {} catch {
            revert("TokenWrapper: Invalid ERC20 implementation");
        }
        try ERC20(token).balanceOf(address(this)) returns (uint256) {} catch {
            revert("TokenWrapper: Invalid ERC20 implementation");
        }
    }

    function _validateAmount(uint256 amount) internal pure {
        require(amount <= MAX_SAFE_AMOUNT, "TokenWrapper: Amount too large");
        require(amount > 0, "TokenWrapper: Zero amount");
    }

    function _validateTokenTransfer(
        uint256 beforeBalance,
        uint256 afterBalance,
        uint256 expectedAmount,
        bool isIncoming
    ) internal pure {
        uint256 actualAmount = isIncoming ? 
            afterBalance - beforeBalance : 
            beforeBalance - afterBalance;
            
        require(
            actualAmount == expectedAmount,
            "TokenWrapper: Token behavior mismatch"
        );
    }

    // Sliding window implementation
    function _cleanupOldOperations(Operation[] storage operations) private {
        uint256 cutoffTime = block.timestamp - WINDOW_SIZE;
        uint256 i = 0;
        while (i < operations.length && operations[i].timestamp < cutoffTime) {
            i++;
        }
        if (i > 0) {
            uint256 j = 0;
            while (i < operations.length) {
                operations[j] = operations[i];
                j++;
                i++;
            }
            while (operations.length > j) {
                operations.pop();
            }
        }
    }

    function _getSlidingWindowVolume(Operation[] storage operations) private view returns (uint256) {
        uint256 volume = 0;
        uint256 cutoffTime = block.timestamp - WINDOW_SIZE;
        
        for (uint256 i = 0; i < operations.length; i++) {
            if (operations[i].timestamp >= cutoffTime) {
                volume += operations[i].amount;
            }
        }
        
        return volume;
    }

    function _updateSlidingWindow(
        Operation[] storage operations,
        uint256 amount,
        uint256 maxAmount
    ) private {
        _cleanupOldOperations(operations);
        
        uint256 currentVolume = _getSlidingWindowVolume(operations);
        require(
            currentVolume + amount <= maxAmount,
            "TokenWrapper: Rate limit exceeded"
        );
        
        operations.push(Operation(amount, block.timestamp));
    }

    // Core functions with security measures
    function wrap(uint256 amount) external nonReentrant {
        require(!isEmergencyMode, "TokenWrapper: Emergency mode active");
        _validateAmount(amount);
        
        _updateSlidingWindow(
            wrapOperations[msg.sender],
            amount,
            maxWrapPerWindow
        );

        uint256 initialBalance = balanceOf(msg.sender);
        uint256 initialUnderlyingBalance = underlyingToken.balanceOf(address(this));
        
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        _validateTokenTransfer(
            initialUnderlyingBalance,
            underlyingToken.balanceOf(address(this)),
            amount,
            true
        );
        
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

    function wrapWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        require(!isEmergencyMode, "TokenWrapper: Emergency mode active");
        _validateAmount(amount);
        
        if (address(underlyingToken).code.length > 0) {
            try IERC20Permit(address(underlyingToken)).permit(
                msg.sender,
                address(this),
                amount,
                deadline,
                v,
                r,
                s
            ) {} catch {}
        }

        wrap(amount);
    }

    function unwrap(uint256 amount) external nonReentrant {
        require(!isEmergencyMode, "TokenWrapper: Emergency mode active");
        _validateAmount(amount);
        require(amount % scalingFactor == 0, "TokenWrapper: Invalid amount");
        
        uint256 underlyingAmount = amount / scalingFactor;
        _updateSlidingWindow(
            unwrapOperations[msg.sender],
            underlyingAmount,
            maxUnwrapPerWindow
        );

        uint256 initialBalance = balanceOf(msg.sender);
        uint256 initialUnderlyingBalance = underlyingToken.balanceOf(address(this));
        
        require(
            underlyingAmount <= underlyingToken.balanceOf(address(this)),
            "TokenWrapper: Insufficient underlying balance"
        );
        
        _burn(msg.sender, amount);
        
        underlyingToken.safeTransfer(msg.sender, underlyingAmount);
        
        _validateTokenTransfer(
            initialUnderlyingBalance,
            underlyingToken.balanceOf(address(this)),
            underlyingAmount,
            false
        );
        
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

    // Emergency functions
    function setEmergencyMode(bool _isEmergencyMode) external onlyOwner {
        isEmergencyMode = _isEmergencyMode;
        emit EmergencyModeSet(_isEmergencyMode);
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(isEmergencyMode, "TokenWrapper: Not in emergency mode");
        IERC20(token).safeTransfer(owner(), amount);
        emit EmergencyWithdraw(token, amount);
    }

    // Admin functions
    function setRateLimits(
        uint256 _maxWrapPerWindow,
        uint256 _maxUnwrapPerWindow
    ) external onlyOwner {
        require(_maxWrapPerWindow > 0 && _maxWrapPerWindow <= MAX_SAFE_AMOUNT, "TokenWrapper: Invalid wrap limit");
        require(_maxUnwrapPerWindow > 0 && _maxUnwrapPerWindow <= MAX_SAFE_AMOUNT, "TokenWrapper: Invalid unwrap limit");
        maxWrapPerWindow = _maxWrapPerWindow;
        maxUnwrapPerWindow = _maxUnwrapPerWindow;
        emit RateLimitsUpdated(_maxWrapPerWindow, _maxUnwrapPerWindow);
    }

    // View functions
    function getUnderlyingAmount(uint256 wrappedAmount) public view returns (uint256) {
        return wrappedAmount / scalingFactor;
    }

    function getWrappedAmount(uint256 underlyingAmount) public view returns (uint256) {
        return underlyingAmount * scalingFactor;
    }

    function getUnderlyingDecimals() external view returns (uint8) {
        return underlyingDecimals;
    }

    function getCurrentWindowVolume(address user, bool isWrap) external view returns (uint256) {
        Operation[] storage operations = isWrap ? wrapOperations[user] : unwrapOperations[user];
        return _getSlidingWindowVolume(operations);
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
    event EmergencyModeSet(bool isEmergencyMode);
    event EmergencyWithdraw(address indexed token, uint256 amount);
}
