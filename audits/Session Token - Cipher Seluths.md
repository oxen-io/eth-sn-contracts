---
title: Introduction

---

# Introduction

A security review of the **Oxen Blockchain** smart contract was done by **Cipher Seluths** team, with a focus on the security aspects of the smart contracts implementation.

# Disclaimer

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource and expertise bound effort where we try to find as many vulnerabilities as possible. we can not guarantee 100% security after the review or even if the review will find any problems with your smart contracts. Subsequent security reviews, bug bounty programs and on-chain monitoring are strongly recommended.

# About **Cipher Seluths**

**Cipher Seluths** is team of security researchers [**Udsen**](https://code4rena.com/@Udsen) & [**Viraz**](https://twitter.com/Viraz04) who have a good experience participating in codearena contests both solo and as a team & have found multiple vulnerabilities in various protocols.

# About **Oxen Blockchain**

The Oxen blockchain is a private payments system that enables the creation of many privacy-preserving applications
The Oxen blockchain and the $OXEN token are at the heart of Oxen. Together they bring privacy, incentivisation, and decentralisation to the Oxen Blockchain tech stack.


# Severity classification

| Severity               | Impact: High | Impact: Medium | Impact: Low |
| ---------------------- | ------------ | -------------- | ----------- |
| **Likelihood: High**   | Critical     | High           | Medium      |
| **Likelihood: Medium** | High         | Medium         | Low         |
| **Likelihood: Low**    | Medium       | Low            | Low         |

**Impact** - the technical, economic and reputation damage of a successful attack

**Likelihood** - the chance that a particular vulnerability gets discovered and exploited

**Severity** - the overall criticality of the risk

# Security Assessment Summary

**_review commit hash_ - [e3f6bdc4eef75bce44b44e076cae0e6163b046e4](https://github.com/oxen-io/eth-sn-contracts)**

# Detailed Findings
## H-01 Attacker can enable DOS by front running the claiming of network rewards by the user

### Lines of code

https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L128


## Vulnerability details

### Impact
The user managing the service nodes can be front run by an attacker resulting in them unable to claim less rewards/no reward or their claim tx being reverted

### Proof of Concept
The `updateRewardsBalance` method is used to set the rewards that can be claimable by the user managing a particular serivice node and then the user can call `claimRewards` method to claim the rewards

There is a BLS signature verification that happens before the reward amount is updated
```
BN256G2.G2Point memory signature = BN256G2.G2Point([sigs1,sigs0],[sigs3,sigs2]);

bytes memory encodedMessage = abi.encodePacked(rewardTag, recipientAddress, recipientAmount);

BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(encodedMessage)));

if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), Hm)) revert InvalidBLSSignature();
```

The issue is in the signed message `msg.sender` isn't checked and there is no mechanism for signature expiry as well which means a attacker can re-use the same sig the user used and set the reward amount as 0 or a lower amount then set by the user before and hence create DOS when a user tries to claim rewards

Here is an example which demonstrates the same
```
the user calls updateRewardsBalance and sets the reward amount as 15 tokens and then signs the claim tx

the attacker now front runs the claim tx and calls updateRewardsBalance again with the old signature and sets the reward amount for the user as 0

so now when the claim tx initiated by the user reaches finality they don't get any rewards
```

### Tools Used
manual review
### Recommended Mitigation Steps
change `bytes memory encodedMessage = abi.encodePacked(rewardTag, recipientAddress, recipientAmount);` to `bytes memory encodedMessage = abi.encodePacked(rewardTag, msg.sender, recipientAmount);` so the signature cannot be used by someone else and also add a mapping to ensure 1 signature can only be used once

## M-01 A whale can get the control of the protocol by having a mojority of stake in the network

### Lines of code

https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L191


## Vulnerability details

### Impact
A single whale can stake large amount of session tokens and create majority of the ServiceNodes thus controlling the key functionalities of the protocol where majority of the ServiceNode signatures are needed for execution and hence create a DOS situtation

### Proof of Concept
The `ServiceNodeRewards` contract allows any user to create `any number of ServiceNodes` to the protocol by adding the `BLSPublicKey` by calling the `ServiceNodeRewards.addBLSPublicKey` function with proof of possession BLS signature .

But the issue here is that a single whale can stake large amount of session tokens and create majority of the ServiceNodes thus controlling the key functionalities of the protocol where majority of the ServiceNode signatures are needed for execution (Such as `removeBLSPublicKeyWithSignature` and `liquidateBLSPublicKeyWithSignature`).

This issue is prevalent specially at the early stages of the protocol where lot of ServiceNodes are not added into the protocol. For example if there are `100 nodes` the `blsNonSignerThreshold` will be `33`. Hence if a single whale user can have the ownership of `67 nodes` he can control the vital operations of the network.

When a normal user tries to add more nodes to the network by calling the `addBLSPublicKey` function the whale user can `front run` the same `transaction` with the `same pubkey` and `same signature` and add that node as if it was his. The signature does not have the `msg.sender` and hence this is possible. So when the `normal user's transaction` is executed the following condition in the `ServiceNodeRewards._addBLSPublicKey` will revert. 

```solidity
        uint64 serviceNodeID = serviceNodeIDs[BN256G1.getKeyForG1Point(pubkey)];
        if(serviceNodeID != 0) revert BLSPubkeyAlreadyExists(serviceNodeID);
```

The whale can later `remove` this node from the network and get his `funds back` by calling the `removeBLSPublicKeyWithSignature`. As a result the attacker can get the control of the `ServiceNodeRewards` contract since he can single handedly perform `updateRewardBalance`, `Node removal`, `Node liquidation` and can `grief` other users from performing the same operations as well.

Further this could `grief the other users` from `removing their nodes` from the protocol and getting thier `staked amount` and `claimable rewards` from the protocol which is `loss of funds` to the other stakers.

### Tools Used
manual review
### Recommended Mitigation Steps
Hence it is recommended to `limit the number of ServiceNodes` a `single user (msg.sender)` can `add` to the protocol by introducing a upperbound per single address and maintaining a mapping of `address->uint256`.
Or even this upperbound can be a percentage of the total nodes (totalNodes) of the network at a given time.

In addition `Tokenomics` can be planned in a way, to ensure the cost of a node is sufficiently high so that whales can't achieve 300+ nodes easily.

## M-02 pool liquidation share is rounded down

### Lines of code
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L357

## Vulnerability details

### Impact
The network get's less liquidation fee than it should

### Proof of Concept
Usually during a liquidation event, the liquidation fee is calculated in favour of the protocol i.e the calculation result for the protocol's share is always rounded up, but here the result is rounded down since solidity always rounds the result down during division hence the liquidation share of the netowrk is reduced
```
deposit * poolShareOfLiquidationRatio/ratioSum
```

### Tools Used
manual review
### Recommended Mitigation Steps
The calculation of the `protocol share` should be such that the `protocol share` should be rounded up.This can be done by using a `ceil` method of any `math library`.

## M-03 remove BLS public key check is inconsistent
### Lines of code
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L296

## Vulnerability details

### Impact
bls public key can be removed when `block.timestamp == leaveRequestTimestamp`

### Proof of Concept
The comment on top of `removeBLSPublicKeyAfterWaitTime` states that 
`Removes a BLS public key after a specified wait time` but the check where the current timestamp is same as `leaveRequestTimestamp` the transaction does not revert breaking the invaraint of the netowrk

### Tools Used
manual review
### Recommended Mitigation Steps
change `        if(block.timestamp < timestamp) revert LeaveRequestTooEarly(serviceNodeID, timestamp, block.timestamp);
` to `if(block.timestamp <= timestamp) revert LeaveRequestTooEarly(serviceNodeID, timestamp, block.timestamp);`

# Quality Assuarance

## L-01 Missing pause functionality in the `ServiceNodeRewards` contract

### Impact
The network can `remove` the ServiceNode via a liquidation. But if the liquidation is done to decommission fradulent nodes in the event of an attack, the `attacker` can `effect` the `operations` of the protocol till he is decommissioned.

### Tools Used
Manual review

### Recommended Mitigation Steps
It is recommended to add the `pause functionality` to the contract to `pause` `addition` of the BLS pub keys (ServiceNodes), `removal` of it (in the event of an attack) and `claim reward` operations, as an additional security measure

## L-02 Attacker can enable DOS by preventing a user adding a service node again

# Lines of code

https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L191


# Vulnerability details

## Impact
The user managing a service node can be front run by an attacker if a service node added by the user is liquidated, then the attacker can use the same public key and hence add the node again, preventing the user from adding it again

## Proof of Concept
The `_addBLSPublicKey` method is used to add a new service node, for the proof of possession verification we see
```
BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(proofOfPossessionTag, pubkey.X, pubkey.Y))));
```
where the `pubkey` is derived here `BN256G1.G1Point memory pubkey = BN256G1.G1Point(pkX, pkY);` and `pkX` & `pkY` are function parameters which means that the pub key can reused by anyone since there is no check on the msg.sender during proof of possession verification

So consider a scenario where a user adds a new service node and it get's liquidated after some time, now a attacker can add the node again by passing the same `pkX` & `pkY` values and this prevents the user from using their own pubkey and adding the node again

## Tools Used
manual review
## Recommended Mitigation Steps
change `BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(proofOfPossessionTag, pubkey.X, pubkey.Y))));` to `BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(proofOfPossessionTag, msg.sender, pubkey.X, pubkey.Y))));` so the signature cannot be used by someone else and also add a mapping to ensure 1 signature can only be used once

## L-03 `leaveRequestTimestamp` is not checked if it is set or not when `removeBLSPublicKeyWithSignature` is called

# Lines of code
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L273

# Vulnerability details

## Impact
users can bypass the `initiateRemoveBLSPublicKey` method when removing their code by calling `removeBLSPublicKeyWithSignature` directly

## Proof of Concept
`initiateRemoveBLSPublicKey` has a comment which states that `Should be called first and later once the network is happy for node to exist the user should call `removeBLSPublicKeyWithSignature` with a valid BLS signature returned by the network` and hence `leaveRequestTimestamp` is set there

the issue is that in `removeBLSPublicKeyWithSignature` method `leaveRequestTimestamp` is not checked so the users essentially can by pass the `initiateRemoveBLSPublicKey` method which breaks the protocol invariant

## Tools Used
manual review
## Recommended Mitigation Steps
add a check in `removeBLSPublicKeyWithSignature`
```
if(block.timestamp <= leaveRequestTimestamp) revert();
```

## L-04 Recommended to use `openzeppelin Ownable2Step` in place of `Ownable`

### Lines of code
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L6
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L12

### Impact
Here the single-step ownership transfer pattern is used. If by mistake the current owner provides an incorrect address as the new owner when calling the `Ownable.transferOwnership` function, then none of the `onlyOwner` methods (seedPublicKeyList, start) of the `ServiceNodeRewards` contract will be callable again. The recommended solution will be to use the `two-step ownership transfer` pattern. Using the two-step process the `new owner` will have to `first claim the ownership` and then the `ownership` will be `transferred to him`.

### Tools Used
Manual review

### Recommended Mitigation Steps
It is recommended to use `Ownable2Step` of OpenZeppelin and use the `two-step ownership transfer` pattern.

## L-05 `renounceOwnership` function in the inherited openzeppelin `Ownable.sol` contract should be overridden to revert if called 

### Impact

The Ownable.sol has the` renounceOwnership()` function which is `callable` by the `owner` to `renounce` the `ownership` of the contract to `address(0)` as shown below. 

```solidity
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
```

This is a `virtual` function and it is `recommended` to `overwrite` this function in the `ServiceNodeRewards.sol` contract such that the `renounceOwnership` will `revert` if `called`. Hence the Owner is not able to renounce the ownerhsip of the contract to address(0). 

### Tools Used
Manual review

### Recommended Mitigation Steps

Recommended to override the `renounceOwnership` function inside the `ServiceNodeRewards` contract such that the transaction will revert if the `owner` calls the `renounceOwnership` function by mistake or intentionally to `sabotage` the contract.

```solidity
    function renounceOwnership() public override onlyOwner {
        revert;
    }
```

## L-06 `sumAmounts` variable defined and computed in the `ServiceNodeRewards.seedPublicKeyList` function is not used

### Lines of code
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L367
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L382

### Impact

The `ServiceNodeRewards.seedPublicKeyList` function is used to add a list of nodes that are already acting as service nodes in the protocol. And the `staked amounts` for each of the nodes to be added is passed in to the function via `uint256[] calldata amounts` input array. 

Then each of these nodes are added to the `serviceNodes` linked list and the respective `amounts` are added to the local variable `sumAmounts` as shown below:

```solidity
    sumAmounts = sumAmounts + amounts[i]; 
```

But this `sumAmounts` variable is never used within the scope of the function. The initial assumption was the `sumAmounts` was calculated to transfer the staked amount to the `ServiceNodeRewards` contract after the `seedList` of nodes are added to the `serviceNodes` linked list, at the end of the `ServiceNodeRewards.seedPublicKeyList` function. 

But since the staked amount transfer for `seedPublicKeyList` nodes are handled by the `foundation` itself currently this `sumAmounts` variable is redundant.

## L-07 Redundant check `serviceNodeRecipient == address(0)` can be omitted in the `ServiceNodeRewards._initiateRemoveBLSPublicKey` function

### Lines of code
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L249-L251
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L259-L260

### Impact

In the `ServiceNodeRewards._initiateRemoveBLSPublicKey` function the following check is redundant,

```solidity
        if(serviceNodeRecipient == address(0)) revert RecipientAddressNotProvided(serviceNodeID); 
```

Due to following reasons:

The `_initiateRemoveBLSPublicKey` is called in the `initiateRemoveBLSPublicKey` function, as follows with the `recipient == msg.sender` and the `msg.sender != 0`.

```soldity
    function initiateRemoveBLSPublicKey(uint64 serviceNodeID) public {
        _initiateRemoveBLSPublicKey(serviceNodeID, msg.sender);
    }
```

And the check `serviceNodeRecipient != recipient` in the `_initiateRemoveBLSPublicKey` after the `serviceNodeRecipient == address(0)` check, ensures that the `serviceNodeRecipient !=0` since the `recipient != 0` as explained above.

```solidity
        if(serviceNodeRecipient != recipient) revert RecipientAddressDoesNotMatch(serviceNodeRecipient, recipient, serviceNodeID); 
```

And the `_initiateRemoveBLSPublicKey` is an `internal function` which is called only `once` in the ServiceNodeRewards contract and this contract is `not inherited` by any other contract.

### Tools Used
Manual review

### Recommended Mitigation Steps

Hence it is recommended to remvoe the redundant check `serviceNodeRecipient == address(0)` in the `ServiceNodeRewards._initiateRemoveBLSPublicKey` since it is anyway checked in the subsequent check.

## L-08 The `ServiceNodeRewards.seedPublicKeyList()` function should only be called before the `hardfork`, but no logic implementation to ensure that

### Lines of code
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L360
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L364-L403

### Impact

The `natspec` comments for the `ServiceNodeRewards.seedPublicKeyList()` function states the following:

```solidity
Only should be called before the hardfork by the foundation to ensure the public key list is ready to operate
```

But there is `no logic implementation` in the `seedPublicKeyList` function to `ensure` that this function can `only be called before` the `hardfork`. Hence the `seedPublicKeyList` function can be called after the `hardfork` to add more `ServiceNodes` to the protocol by the `foundation`.

### Tools Used
Manual review

### Recommended Mitigation Steps

Hence it is recommended to configure a logic in the `seedPublicKeyList()` function to ensure that the function can only be called before the hardfork by the foundation. Any call after the hardfork to the `seedPublicKeyList()` function should revert which is the intended behaviour of the function aligning with the natspec comment.

## L-09 The `totalNodes` state variable is not incremented inside the `for loop` of the `ServiceNodeRewards.seedPublicKeyList` function

### Lines of code
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L401
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L371-L396

### Impact

The `ServiceNodeRewards.seedPublicKeyList` function is used by the `foundation` to add a list of nodes that are `already acting` as `service nodes` in the `protocol`.

In the `logic implementation` of the `seedPublicKeyList` function the `Seed ServiceNodes` are added one by one iterating through a `for loop`. 

But the issue is the `totalNodes` state variable is not incremented inside the `for loop` but only increments after the `for loop` ends. But the `updateServiceNodesLength` function implementation suggests that the `totalNodes = serviceNodesLength()` which means the number of service nodes added to the protocol is equal to the length of the `serviceNodes` linked list.

As a result irrespecitve of number of `Seed ServiceNodes` added by the foundation via the `seedPublicKeyList` function the `totalNodes = 1` after the execution which is erroneous and a broken state.

### Tools Used
Manual review

### Recommended Mitigation Steps

Hence it is recommended to increment the `totalNodes` inside the `for loop` which is used to add `Seed ServiceNodes` in the `ServiceNodeRewards.seedPublicKeyList` function.

# Informational

## I-01 Typo in the natspec comment

### Lines of code
https://github.com/oxen-io/eth-sn-contracts/blob/master/contracts/ServiceNodeRewards.sol#L247

### Impact

There is a type in the following natspec comment in the `exist` word and should be `exit` instead.

```solidity
Should be called first and later once the network is happy for node to exist the user should call removeBLSPublicKeyWithSignature with a valid BLS signature returned by the network
```

### Tools Used
Manual review

### Recommended Mitigation Steps
Typo exist in the above mentioned natspec comment should be corrected as `exit`. Proper natspec commenting will improve the code readability and understanding for the developers and auditors.

# Gas Optimisations

## G-01 Use compiler version >= 0.8.22 or use `unchecked` in for loops

The for loops used have the counter operation together with the counter initialisation which costs extra gas everytime there is a counter increment so it is recomended to either use a compiler version >= 0.8.22 or do the counter operation in the unchecked block i.e 
```
for(uint256 i; i < length;) 
{ .
  .
  .
  unchecked { 
   += i;
  }
}
```

## G-02 Variables only initialized in the constructor should be marked as immutable

`stakingRequirement, liquidatorRewardRatio, poolShareOfLiquidationRatio & recipientRatio` are only initialized in the constructor and not updated anywhere else so these variables should be marked as immutable to save gas

# Other Suggestions
We strongly recommend that the test coverage of the contracts should be close to 100%, static analysers like slither should also be used for marking and fixing any issues identified there.
