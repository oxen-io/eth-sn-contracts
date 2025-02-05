#!/usr/bin/python3

# Session Token stakable vesting contract script.  This script scans a list of deployed stakable
# vesting contracts, dumping the contract values.
#
# To run it, you need various Python dependencies (easily installed via pip or system
# dependencies), and an Arbitrum node.

from web3 import Web3, middleware, exceptions as w3ex
import requests
from eth_account import Account
from solcx import compile_source, install_solc
import argparse
import sys
import os
from Crypto.Hash import keccak
import time
from terminaltables import SingleTable


parser = argparse.ArgumentParser(
    prog="ls-vesting", description="Vesting contract lister"
)

parser.add_argument("-l", "--l2", required=True, help="L2 provider URL", metavar="URL")
parser.add_argument(
    "-S", "--sesh", help="SESH token address to validate", metavar="0x..."
)
parser.add_argument(
    "-R", "--rewards", help="SN Rewards contract address to validate", metavar="0x..."
)
parser.add_argument(
    "-K", "--revoker", help="Revoker address to validate", metavar="0x..."
)
parser.add_argument(
    "-C",
    "--contrib",
    help="Multicontributor factor contract address to validate",
    metavar="0x...",
)

parser.add_argument(
    "contracts",
    nargs="+",
    help="Stakable vesting contracts to query",
    metavar="0xContractAddr",
)

args = parser.parse_args()

print(f"Loading contracts...")
basedir = os.path.dirname(__file__) + "/.."
install_solc("0.8.26")
compiled_sol = compile_source(
    """
import "SESH.sol";
import "utils/TokenVestingStaking.sol";
""",
    base_path=basedir,
    include_path=f"{basedir}/contracts",
    solc_version="0.8.26",
    revert_strings="debug",
    import_remappings={
        "@openzeppelin/contracts": "node_modules/@openzeppelin/contracts",
        "@openzeppelin/contracts-upgradeable": "node_modules/@openzeppelin/contracts-upgradeable",
    },
)

w3 = Web3(Web3.HTTPProvider(args.l2))
if not w3.is_connected():
    print("L2 connection failed; check your --l2 value", file=sys.stderr)
    sys.exit(1)

actual_chain = w3.eth.chain_id
chain_name, explore_url = (
    ("Arbitrum One", "https://arbiscan.io")
    if actual_chain == 0xA4B1
    else (
        ("Arbitrum Sepolia", "https://sepolia.arbiscan.io")
        if actual_chain == 0x66EEE
        else ("Unknown!", "https://UNKNOWN")
    )
)


def tx_url(txid):
    return f"https://{explore_url}/tx/{txid}"


def get_contract(name, addr):
    return w3.eth.contract(address=addr, abi=compiled_sol[name]["abi"])

def validate(expected, value):
    if expected:
        if expected == value:
            return "✅"
        return f"⛔ {value}"
    return value


results = [
    [
        "Vesting Contract Address",
        "SESH",
        "Beneficiary",
        "Rvokd",
        "Rvokr",
        "Rewards",
        "Contrib",
        "Trnsfr",
    ]
]
for caddr in args.contracts:
    try:
        contract = get_contract(
            "utils/TokenVestingStaking.sol:TokenVestingStaking", caddr
        )
        c = contract.functions
        sesh, bene, revoked, revoker, rewards, contrib, transfer = (
            x().call()
            for x in (
                c.SESH,
                c.beneficiary,
                c.revoked,
                c.revoker,
                c.rewardsContract,
                c.snContribFactory,
                c.transferableBeneficiary,
            )
        )
        SESH = get_contract("SESH.sol:SESH", sesh).functions
        balance = SESH.balanceOf(c.address).call()
        b1 = balance // 1000000000
        b2 = balance % 1000000000
        results.append(
            [
                c.address,
                f"{b1}.{b2:09d} {validate(args.sesh, sesh)}",
                bene,
                revoked,
                validate(args.revoker, revoker),
                validate(args.rewards, rewards),
                validate(args.contrib, contrib),
                transfer,
            ]
        )

    except Exception as e:
        print(f"An error occured with {caddr}: {e}")
        results.append([c.address] + ["N/A"] * 7)


print(f"\n\nResults for chain 0x{actual_chain:x} ({chain_name}):\n")

if args.sesh or args.revoker or args.rewards or args.contrib:
    print(f"\nValidations:")
    if args.sesh:
        print(f"✅ = SESH token address {args.sesh}")
    if args.revoker:
        print(f"✅ = Revoker address {args.revoker}")
    if args.rewards:
        print(f"✅ = Rewards contract address {args.rewards}")
    if args.contrib:
        print(f"✅ = Multicontrib contract address {args.contrib}")
    print()

table = SingleTable(results)
for i in range(8):
    table.justify_columns[i] = 'center'
print(table.table)
