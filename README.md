Wrapper for OPRS Token on BSC Chain https://bscscan.com/address/0x3afc7c9a7d1ac2e78907dffb840b5a879ba17af7

ERC20Wrapper Security Audit Report
--------------------------------------
--------------------------------------

Overview
--------------------------------------
The ERC20Wrapper contract is designed to wrap 0-decimal and 8-decimal ERC20 tokens into 18-decimal versions, implementing comprehensive security measures including sliding window rate limiting and transfer validation.

8-decimal to 18 decimals was deployed here https://bscscan.com/tx/0xaf55935887309e4e20693e33e5ca5a276e0196d624438d5ecf0cbdfa5b776d93 for the bridged Denario Token https://interchain.axelar.dev/polygon/0xce4D3160705fEBb069617A9AD919753055B56e49  (from https://denario.swiss ) to be used as collateral in the oracle free dollar ecosystem on binance. Mamimal transacations per hour 2, maximal tokens for wrapping per hour 500.

0-decimal to 18 decimal was be deployed here https://bscscan.com/tx/0xb049e76e11f5c4c2e7c5735b0e41539b30288a42f60c5fc248adbd53558c41ce for the bridged Operal Equity Token https://invest.operal.solutions  https://interchain.axelar.dev/polygon/0x4Ab946731717d09366B65069eBC8A2C518793801 on BSC

Key Security Features
--------------------------------------

✅ Implemented Protections

Sliding Window Rate Limiting

Per-user operation tracking
1-hour time window
Automatic operation cleanup


Transfer Safety

Transfer amount verification
SafeERC20 implementation
Balance validation checks


Rate Controls

Per-transaction limits
Configurable parameters
Per-user tracking


Core Security

ReentrancyGuard implementation
Proper balance validation
Clear error messages
Immutable critical variables



Security Analysis
Protected Against

✅ Flash loan attacks via sliding window

✅ Transfer fee tokens through amount verification

✅ Reentrancy attacks

✅ Basic overflow/underflow

✅ Insufficient balance issues

✅ Rate manipulation







