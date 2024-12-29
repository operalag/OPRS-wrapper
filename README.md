Wrapper for OPRS Token on BSC Chain https://bscscan.com/address/0x3afc7c9a7d1ac2e78907dffb840b5a879ba17af7

-----------------------------------------------------
-----------------------------------------------------

WORK IN PROGRESS NOT MITIGATED RISK

----------------------------------------------------
-----------------------------------------------------

NOT YET MITIGATED RISKS:

Flash Loan Vulnerability:

No rate limiting
No maximum transaction size per block
Could be used to manipulate connected DEX prices


Token Compatibility:

No specific handling for fee-on-transfer tokens
No handling for rebasing tokens
No blacklist for known malicious tokens


Emergency Controls:

No pause mechanism
No emergency withdrawal function
No way to handle stuck tokens


Approval Front-Running:

No EIP-2612 permit support
Standard ERC20 approvals could be front-run


Contract Upgrade Path:

No upgrade mechanism if bugs are found
Immutable variables can't be changed if needed


Gas Optimization:

No minimum wrap/unwrap amounts to prevent dust
No gas limit checks for token operations


Token Standard Compliance:

Limited validation of underlying token implementation
No checks for return values consistency

-----------------------------------------------------
-----------------------------------------------------

ALREADY MITIGATED RISKS:
-----------------------------------------------------
-----------------------------------------------------

Reentrancy:

Uses ReentrancyGuard modifier
Follows checks-effects-interactions pattern
Burns tokens before transfer in unwrap


Token Transfer Safety:

Uses SafeERC20 library
Verifies actual transfer amounts received
Checks balances before and after transfers


Input Validation:

Zero address checks
Non-empty name/symbol validation
Amount > 0 checks
Maximum balance limit
Token decimals validation


Decimal Precision:

Validates underlying decimals ≤ 18
Checks for valid scaling in unwrap (amount % scalingFactor == 0)
Immutable scaling factor prevents manipulation


Balance Tracking:

Detailed event logging with before/after balances
Balance verification for both tokens
Checks for sufficient balances before operations



