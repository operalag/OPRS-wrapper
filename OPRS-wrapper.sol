// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ERC20Wrapper
 * @notice A secure wrapper for an ERC20 token with 0 decimals, creating a token with 18 decimals.
 */
contract ERC20Wrapper is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Underlying token and parameters
    IERC20 public immutable underlyingToken;
    uint256 private immutable scalingFactor;

    // Rate limiting parameters
    uint256 public maxWrapPerTx;
    uint256 public maxUnwrapPerTx;
    uint256 public constant WINDOW_SIZE = 1 hours;

    struct Operation {
        uint256 amount;
        uint256 timestamp;
    }

    mapping(address => Operation[]) private wrapOperations;
    mapping(address => Operation[]) private unwrapOperations;

    // Events
    event Wrapped(address indexed user, uint256 underlyingAmount, uint256 wrappedAmount);
    event Unwrapped(address indexed user, uint256 wrappedAmount, uint256 underlyingAmount);
    event RateLimitsUpdated(uint256 maxWrapPerTx, uint256 maxUnwrapPerTx);

    /**
     * @dev Constructor
     * @param _underlyingToken Address of the underlying token (must have 0 decimals).
     * @param _name Name of the wrapped token.
     * @param _symbol Symbol of the wrapped token.
     * @param _maxWrapPerTx Maximum amount of tokens that can be wrapped per transaction.
     * @param _maxUnwrapPerTx Maximum amount of tokens that can be unwrapped per transaction.
     */
    constructor(
        address _underlyingToken,
        string memory _name,
        string memory _symbol,
        uint256 _maxWrapPerTx,
        uint256 _maxUnwrapPerTx
    ) ERC20(_name, _symbol) {
        require(_underlyingToken != address(0), "ERC20Wrapper: Invalid token address");

        // Validate underlying token interface
        require(_validateToken(_underlyingToken), "ERC20Wrapper: Invalid ERC20 implementation");

        underlyingToken = IERC20(_underlyingToken);

        // Ensure the token has 0 decimals
        require(ERC20(_underlyingToken).decimals() == 0, "ERC20Wrapper: Token must have 0 decimals");

        scalingFactor = 1e18; // Scaling factor to convert 0 decimals to 18 decimals
        maxWrapPerTx = _maxWrapPerTx;
        maxUnwrapPerTx = _maxUnwrapPerTx;
    }

    /**
     * @dev Updates the maximum transaction limits.
     * @param _maxWrapPerTx Maximum amount that can be wrapped per transaction.
     * @param _maxUnwrapPerTx Maximum amount that can be unwrapped per transaction.
     */
    function updateRateLimits(uint256 _maxWrapPerTx, uint256 _maxUnwrapPerTx) external onlyOwner {
        require(_maxWrapPerTx > 0, "ERC20Wrapper: Invalid wrap limit");
        require(_maxUnwrapPerTx > 0, "ERC20Wrapper: Invalid unwrap limit");

        maxWrapPerTx = _maxWrapPerTx;
        maxUnwrapPerTx = _maxUnwrapPerTx;

        emit RateLimitsUpdated(_maxWrapPerTx, _maxUnwrapPerTx);
    }

    /**
     * @dev Internal function to clean up outdated operations.
     */
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

    /**
     * @dev Wraps the underlying token into the wrapped token.
     * @param amount The amount of the underlying token to wrap.
     */
    function wrap(uint256 amount) external nonReentrant {
        require(amount > 0, "ERC20Wrapper: Amount must be greater than 0");
        require(amount <= maxWrapPerTx, "ERC20Wrapper: Exceeds maximum wrap limit");

        _cleanupOldOperations(wrapOperations[msg.sender]);

        uint256 totalWrapped = _getSlidingWindowVolume(wrapOperations[msg.sender]);
        require(totalWrapped + amount <= maxWrapPerTx, "ERC20Wrapper: Rate limit exceeded");

        uint256 balanceBefore = underlyingToken.balanceOf(address(this));
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualReceived = underlyingToken.balanceOf(address(this)) - balanceBefore;
        require(actualReceived == amount, "ERC20Wrapper: Transfer amount mismatch");

        wrapOperations[msg.sender].push(Operation(amount, block.timestamp));

        uint256 wrappedAmount = amount * scalingFactor;
        _mint(msg.sender, wrappedAmount);

        emit Wrapped(msg.sender, amount, wrappedAmount);
    }

    /**
     * @dev Unwraps the wrapped token into the underlying token.
     * @param amount The amount of the wrapped token to unwrap (must be in 18 decimals).
     */
    function unwrap(uint256 amount) external nonReentrant {
        require(amount > 0, "ERC20Wrapper: Amount must be greater than 0");
        require(amount % scalingFactor == 0, "ERC20Wrapper: Amount must align with scaling factor");

        uint256 underlyingAmount = amount / scalingFactor;
        require(underlyingAmount <= maxUnwrapPerTx, "ERC20Wrapper: Exceeds maximum unwrap limit");

        _cleanupOldOperations(unwrapOperations[msg.sender]);

        uint256 totalUnwrapped = _getSlidingWindowVolume(unwrapOperations[msg.sender]);
        require(totalUnwrapped + underlyingAmount <= maxUnwrapPerTx, "ERC20Wrapper: Rate limit exceeded");

        require(
            underlyingToken.balanceOf(address(this)) >= underlyingAmount,
            "ERC20Wrapper: Insufficient underlying balance"
        );

        _burn(msg.sender, amount);
        underlyingToken.safeTransfer(msg.sender, underlyingAmount);

        unwrapOperations[msg.sender].push(Operation(underlyingAmount, block.timestamp));

        emit Unwrapped(msg.sender, amount, underlyingAmount);
    }

    /**
     * @dev Calculates the total volume of operations in the sliding window.
     */
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

    /**
     * @dev Validates the token interface for the underlying token.
     * @param token Address of the token to validate.
     * @return True if the token has a valid ERC20 implementation.
     */
    function _validateToken(address token) private view returns (bool) {
        try IERC20(token).totalSupply() returns (uint256) {} catch {
            return false;
        }
        try IERC20(token).balanceOf(address(this)) returns (uint256) {} catch {
            return false;
        }
        return true;
    }

    /**
     * @dev Returns the scaling factor (always 1e18).
     */
    function getScalingFactor() external view returns (uint256) {
        return scalingFactor;
    }
}
