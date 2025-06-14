Wrapper for OPRS Token on BSC Chain https://bscscan.com/address/0x3afc7c9a7d1ac2e78907dffb840b5a879ba17af7

ERC20Wrapper Security Audit Report
--------------------------------------
--------------------------------------

Overview
--------------------------------------
The ERC20Wrapper contract is designed to wrap 0-decimal and 8-decimal ERC20 tokens into 18-decimal versions, implementing comprehensive security measures including sliding window rate limiting and transfer validation.

DSC Denario Silver Token
------
8-decimal to 18 decimals was deployed here https://bscscan.com/address/0x2f30d9ec8fec8612dbcd54c4c2604ffc972e8a8d for the bridged Denario Token https://interchain.axelar.dev/polygon/0xce4D3160705fEBb069617A9AD919753055B56e49  (from https://denario.swiss ) to be used as collateral in the oracle free dollar ecosystem on binance. Mamimal transacations per hour 2, maximal tokens for wrapping per hour 500. The wrapper contract is on Polygon is here: 0xf3773fa33A89ec29060C3850583309E6737C007A https://polygonscan.com/address/0xf3773fa33A89ec29060C3850583309E6737C007A#code


The interface for wrapping on BSC is accessible here https://wrapper-wizard-denario.lovable.app/ 


OPRS Equity 
------
0-decimal to 18 decimal was be deployed here https://bscscan.com/address/0x8f73610dd60185189657c826df315cc980ca4a0e#code for the bridged Operal Equity Token https://invest.operal.solutions  https://interchain.axelar.dev/polygon/0x4Ab946731717d09366B65069eBC8A2C518793801 on BSC

The wrapper Contract for Polygon can be found here: https://polygonscan.com/address/0xB2BF2689db4ff1e392d95562c3E71dAAF2d1Bc5F#code

DGC Denario Gold Token
------
-The Gold-Token from Denarios https://www.denario.swiss/dgc 

-Axelar Bridge from Polygon to BNB https://interchain.axelar.dev/polygon/0xf7E2D612F1A0ce09ce9fC6FC0b59C7fD5b75042F

-contract has been deployed here https://bscscan.com/address/0x5A3ED6EA3344116A579b11A08E708e093599C13F#code - with a wrong name, proposed position on OFD has been vetoed

-new contract has been deployed here https://bscscan.com/address/0xd9B8CF9f4FD8055c0454389dD6aAB1FDcE2E8781#code

-old wrapper interface is accessible here https://denario-gold-wrapper.lovable.app/ and documented (private repo) here https://github.com/operalag/denario-gold-wrapper

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







