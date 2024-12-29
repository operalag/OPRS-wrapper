// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TokenWrapper
 * @dev Wraps any ERC20 token into an 18 decimal equivalent with enhanced security
 */
contract TokenWrapper is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlyingToken;
    uint8 private immutable underlyingDecimals;
    uint256 private immutable scalingFactor;
    
    // Additional state variables for validation
    uint256 public constant MAX_UNDERLYING_BALANCE = type(uint96).max; // Safe upper limit

    /**
     * @param _underlyingToken Address of the token to wrap
     * @param _name Name for the wrapped token
     * @param _symbol Symbol for the wrapped token
     */
    constructor(
        address _underlyingToken,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_underlyingToken != address(0), "TokenWrapper: Zero address");
        require(bytes(_name).length > 0, "TokenWrapper: Empty name");
        require(bytes(_symbol).length > 0, "TokenWrapper: Empty symbol");
        
        underlyingToken = IERC20(_underlyingToken);
        
        // Validate token interface and get decimals
        try ERC20(_underlyingToken).decimals() returns (uint8 decimals) {
            underlyingDecimals = decimals;
        } catch {
            revert("TokenWrapper: Invalid token interface");
        }
        
        require(underlyingDecimals <= 18, "TokenWrapper: Decimals too high");
        scalingFactor = 10 ** (18 - underlyingDecimals);
    }

    /**
     * @dev Wrap underlying tokens to 18 decimal wrapped tokens
     * @param amount Amount of underlying tokens to wrap
     */
    function wrap(uint256 amount) external nonReentrant {
        require(amount > 0, "TokenWrapper: Zero amount");
        require(
            amount <= MAX_UNDERLYING_BALANCE, 
            "TokenWrapper: Amount exceeds maximum"
        );

        // Cache user's initial balance for event
        uint256 initialBalance = balanceOf(msg.sender);
        uint256 initialUnderlyingBalance = underlyingToken.balanceOf(address(this));
        
        // Transfer underlying tokens from sender
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Verify actual transfer amount
        uint256 receivedAmount = underlyingToken.balanceOf(address(this)) - initialUnderlyingBalance;
        require(receivedAmount == amount, "TokenWrapper: Transfer amount mismatch");
        
        // Mint wrapped tokens to sender
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

    /**
     * @dev Unwrap tokens back to underlying tokens
     * @param amount Amount of wrapped tokens to unwrap
     */
    function unwrap(uint256 amount) external nonReentrant {
        require(amount > 0, "TokenWrapper: Zero amount");
        require(amount % scalingFactor == 0, "TokenWrapper: Invalid amount");
        
        // Cache balances for event
        uint256 initialBalance = balanceOf(msg.sender);
        uint256 initialUnderlyingBalance = underlyingToken.balanceOf(address(this));
        
        // Calculate underlying token amount
        uint256 underlyingAmount = amount / scalingFactor;
        require(
            underlyingAmount <= underlyingToken.balanceOf(address(this)),
            "TokenWrapper: Insufficient underlying balance"
        );
        
        // Burn wrapped tokens first (checks owner's balance)
        _burn(msg.sender, amount);
        
        // Transfer underlying tokens back to sender
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

    /**
     * @dev Returns the amount of underlying tokens that would be received for unwrapping
     * @param wrappedAmount Amount of wrapped tokens
     * @return Amount of underlying tokens
     */
    function getUnderlyingAmount(uint256 wrappedAmount) public view returns (uint256) {
        return wrappedAmount / scalingFactor;
    }

    /**
     * @dev Returns the amount of wrapped tokens that would be received for wrapping
     * @param underlyingAmount Amount of underlying tokens
     * @return Amount of wrapped tokens
     */
    function getWrappedAmount(uint256 underlyingAmount) public view returns (uint256) {
        return underlyingAmount * scalingFactor;
    }

    /**
     * @dev Returns the decimals of the underlying token
     */
    function getUnderlyingDecimals() external view returns (uint8) {
        return underlyingDecimals;
    }

    // Enhanced events with detailed balance tracking
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
}
