import subprocess
import time
import json

RPC = "https://eth-mainnet.g.alchemy.com/v2/p6UDlMQUt1PeyOcmJpF6Y"
CONTRACT = "0x31a4f372aa891b46ba44dc64be1d8947c889e9c6"
PAIR = "0x806b6C6819b1f62Ca4B66658b669f0A98e385D18"

def cast_call(sig, address=CONTRACT):
    cmd = ["cast", "call", address, sig, "--rpc-url", RPC]
    for attempt in range(5):
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return result.stdout.strip()
        time.sleep(2 ** attempt)
    return f"FAILED: {result.stderr}"

def cast_storage(slot, address=CONTRACT):
    cmd = ["cast", "storage", address, str(slot), "--rpc-url", RPC]
    for attempt in range(5):
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return result.stdout.strip()
        time.sleep(2 ** attempt)
    return f"FAILED: {result.stderr}"

# Check key state
queries = [
    ("owner()", "owner()(address)"),
    ("tradingOpen()", "tradingOpen()(bool)"),
    ("swapEnabled()", "swapEnabled()(bool)"),
    ("uniswapOnly()", "uniswapOnly()(bool)"),
    ("totalSupply()", "totalSupply()(uint256)"),
    ("balanceOf(contract)", f"balanceOf(address)(uint256) {CONTRACT}"),
    ("_maxTxAmount()", "_maxTxAmount()(uint256)"),
    ("_taxFee", "_taxFee()(uint256)"),
    ("_teamDev", "_teamDev()(uint256)"),
]

for name, sig in queries:
    time.sleep(3)
    result = cast_call(sig)
    print(f"{name}: {result}")

# Check pair's lastTx - this is a mapping, need to compute storage slot
# mapping (address => uint256) private _lastTx; 
# _lastTx is the 3rd state variable after _rOwned and _tOwned (slot 2)
# But with inheritance, Ownable has _owner at slot 0
# Shoco adds: _rOwned(0), _tOwned(1), _lastTx(2)
time.sleep(3)
# For mapping(address => uint256) at slot 2, the storage slot is keccak256(address . slot)
# But we can try to call the auto-generated getter if it exists... 
# Actually _lastTx is private, no getter.

# Let's check if we can call balanceOf for the pair
time.sleep(3)
result = cast_call(f"balanceOf(address)(uint256) {PAIR}")
print(f"pairBalance: {result}")

# Check if cooldownEnabled is accessible via its auto-generated getter
time.sleep(3)
# Try calling with explicit function signature
result = cast_call("cooldownEnabled()(bool)")
print(f"cooldownEnabled: {result}")

# Check _isSniper for a few addresses
time.sleep(3)
sniper = "0x7589319ED0fD750017159fb4E4d96C63966173C1"
result = cast_call(f"isBlackListed(address)(bool) {sniper}")
print(f"isBlackListed({sniper[:10]}...): {result}")
