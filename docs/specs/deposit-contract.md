# Phase 0 -- Deposit Contract

## Table of contents
<!-- TOC -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Introduction](#introduction)
- [Constants](#constants)
- [Configuration](#configuration)
- [Staking deposit contract](#staking-deposit-contract)
  - [`deposit` function](#deposit-function)
    - [Deposit amount](#deposit-amount)
    - [Withdrawal credentials](#withdrawal-credentials)
    - [`DepositEvent` log](#depositevent-log)
- [Solidity code](#solidity-code)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->
<!-- /TOC -->

## Introduction

This document represents the specification for the beacon chain deposit contract, part of Phase 0.

## Constants

The following values are (non-configurable) constants used throughout the specification.

| Name | Value |
| - | - |
| `DEPOSIT_CONTRACT_TREE_DEPTH` | `2**5` (= 32) |

## Configuration

*Note*: The default mainnet configuration values are included here for spec-design purposes.
The different configurations for mainnet, testnets, and YAML-based testing can be found in the `configs/constant_presets` directory.
These configurations are updated for releases and may be out of sync during `dev` changes.

| Name | Value |
| - | - |
| `DEPOSIT_CHAIN_ID` | `1` |
| `DEPOSIT_NETWORK_ID` | `1` |
| `DEPOSIT_CONTRACT_ADDRESS` | `0x00000000219ab540356cBB839Cbe05303d7705Fa` |

## Staking deposit contract

The initial deployment phases of Ethereum proof-of-stake are implemented without consensus changes to the existing Ethereum execution chain. A deposit contract at address `DEPOSIT_CONTRACT_ADDRESS` is added to the Ethereum execution chain defined by the [chain-id](https://eips.ethereum.org/EIPS/eip-155) -- `DEPOSIT_CHAIN_ID` -- and the network-id -- `DEPOSIT_NETWORK_ID` -- for deposits of ETH to the beacon chain.

_Note_: See [here](https://chainid.network/) for a comprehensive list of public Ethereum chain chain-id's and network-id's.

### `deposit` function

The deposit contract has a public `deposit` function to make deposits. It takes as arguments `bytes calldata pubkey, bytes calldata withdrawal_credentials, bytes calldata signature, bytes32 deposit_data_root`. The first three arguments populate a [`DepositData`](./beacon-chain.md#depositdata) object, and `deposit_data_root` is the expected `DepositData` root as a protection against malformatted calldata.

#### Deposit amount

The amount of ETH (rounded down to the closest Gwei) sent to the deposit contract is the deposit amount, which must be of size at least `MIN_DEPOSIT_AMOUNT` Gwei.

#### Withdrawal credentials

One of the `DepositData` fields is `withdrawal_credentials` which constrains validator withdrawals.
The first byte of this 32-byte field is a withdrawal prefix which defines the semantics of the remaining 31 bytes.
The withdrawal prefixes currently supported are `BLS_WITHDRAWAL_PREFIX` and `ETH1_ADDRESS_WITHDRAWAL_PREFIX`.
Read more in the [validator guide](./validator.md#withdrawal-credentials).

*Note*: The deposit contract does not validate the `withdrawal_credentials` field.
Support for new withdrawal prefixes can be added without modifying the deposit contract.

#### `DepositEvent` log

Every deposit emits a `DepositEvent` log for consumption by the beacon chain. The deposit contract does little validation, pushing most of the validator onboarding logic to the beacon chain. In particular, the proof of possession (a BLS12-381 signature) is not verified by the deposit contract.

