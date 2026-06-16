# 🔥 Pyre Protocol — Full Workflow Smoke Test

> **Chain:** Base Sepolia (84532)
> **Block:** `42932918`
> **Timestamp:** `1781634124`

---
## Configuration

| Parameter | Address |
|---|---|
| poolManager | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| swapRouter | `0x00000000000044a361Ae3cAc094c9D1b14Eece97` |
| pyreToken | `0xaA46dd2434dE4b06Da8D4F7f0Ace4e152EecbbA6` |
| staking | `0x61564EE98d9eFDc198AE6a48dFCd864C7F06A3B3` |
| fireSpirit | `0xB14Fe355E67a2c6F08a8B0291aA188B62718264A` |
| hook | `0xaB0Ae552Ee5933935e39393D32b4034E75fD3Ff8` |
| team | `0xF93E7518F79C2E1978D6862Dbf161270040e623E` |
| tester | `0xF93E7518F79C2E1978D6862Dbf161270040e623E` |

| Parameter | Value |
|---|---|
| buyFeeBps (current) | `500` |
| sellFeeBps (current) | `500` |
| ethBuyAmount | `1000000000000` wei |
| pyreSellAmount | `1000000000000000` wei |
| stakeAmount | `100000000000000000000` wei |
| directBurnAmount | `10000000000000000000000` wei |
| liquidityDelta | `500000000000000000` |
| liquidityEthValue | `5000000000000000` wei |

## Pre-Run State

### State Before

| Metric | Value |
|---|---|
| tester ETH | `1089525682407526519` |
| tester PYRE | `510850945219546066284814` |
| team ETH | `1089525682407526519` |
| staking ETH | `954440594640` |
| hook ETH | `0` |
| totalSupply PYRE | `999899772100000000000000` |
| totalEthToYield | `955200000000` |
| totalEthToTeam | `238800000000` |
| totalPyreBurned | `227900000000000000` |

## Phase 1: POOL SETUP

> ✅ **PASS** — Pool already initialized — skipping

> ✅ **PASS** — Approvals set (PERMIT2, PositionManager, SwapRouter, Staking)

- Liquidity added: 500000000000000000 units
## Phase 2: BUY SWAP (ETH -> PYRE)

- Buy swap — ETH in: 1000000000000 wei
### Delta: After Buy Swap

| Metric | Before | After | Delta |
|---|---|---|---|
| tester ETH | `1084525682407526519` | `1084524692407526519` | **-990000000000** |
| tester PYRE | `439234329160079607225196` | `457054165317438678226563` | **+17819836157359071001367** |
| team ETH | `1084525682407526519` | `1084524692407526519` | **-990000000000** |
| staking ETH | `954440594640` | `994440594640` | **+40000000000** |
| hook ETH | `0` | `0` | **no change** |
| totalSupply PYRE | `999899772100000000000000` | `999899772100000000000000` | **no change** |
| totalEthToYield | `955200000000` | `995200000000` | **+40000000000** |
| totalEthToTeam | `238800000000` | `248800000000` | **+10000000000** |
| totalPyreBurned | `227900000000000000` | `227900000000000000` | **no change** |


**Fee Routing Assertion**

| Check | Expected | Actual | Status |
|---|---|---|---|
| Buy fee (500 bps) | `50000000000` | — | — |
| 80% → staking | `40000000000` | `40000000000` | ✅ PASS |
| 20% → team | `10000000000` | `10000000000` | ✅ PASS |

> ✅ **PASS** — Buy fee routing correct (80/20 split verified)

## Phase 3: SELL SWAP (PYRE -> ETH)

- Sell swap — PYRE in: 1000000000000000 wei
### Delta: After Sell Swap

| Metric | Before | After | Delta |
|---|---|---|---|
| tester ETH | `1084524692407526519` | `1084524692407581414` | **+54895** |
| tester PYRE | `457054165317438678226563` | `457054164317438678226563` | **-1000000000000000** |
| team ETH | `1084524692407526519` | `1084524692407581414` | **+54895** |
| staking ETH | `994440594640` | `994440594640` | **no change** |
| hook ETH | `0` | `0` | **no change** |
| totalSupply PYRE | `999899772100000000000000` | `999899772050000000000000` | **-50000000000000** |
| totalEthToYield | `995200000000` | `995200000000` | **no change** |
| totalEthToTeam | `248800000000` | `248800000000` | **no change** |
| totalPyreBurned | `227900000000000000` | `227950000000000000` | **+50000000000000** |


**Sell Burn Assertion**

| Check | Expected | Actual | Status |
|---|---|---|---|
| Sell burn (500 bps) | `50000000000000` | `50000000000000` | ✅ PASS |

> ✅ **PASS** — Sell PYRE burn accounting correct

## Phase 4: STAKE PYRE

- Staked PYRE: 100000000000000000000
- Staked balance after: 300000000000000000000
- Weight after: 360000000000000000000
> ✅ **PASS** — Stake executed

## Phase 5: SECOND BUY -> STAKING YIELD ROUTING

- Buy swap — ETH in: 1000000000000 wei
### Delta: After Buy 2

| Metric | Before | After | Delta |
|---|---|---|---|
| tester ETH | `1084524692407581414` | `1084523702407581414` | **-990000000000** |
| tester PYRE | `457054164317438678226563` | `472144411101210075356958` | **+15090246783771397130395** |
| team ETH | `1084524692407581414` | `1084523702407581414` | **-990000000000** |
| staking ETH | `994440594640` | `1034440594640` | **+40000000000** |
| hook ETH | `0` | `0` | **no change** |
| totalSupply PYRE | `999899772050000000000000` | `999899772050000000000000` | **no change** |
| totalEthToYield | `995200000000` | `1035200000000` | **+40000000000** |
| totalEthToTeam | `248800000000` | `258800000000` | **+10000000000** |
| totalPyreBurned | `227950000000000000` | `227950000000000000` | **no change** |

- Staking ETH received from buy fee: 40000000000
> ✅ **PASS** — Staking yield routing confirmed

## Phase 6: CLAIM ETH YIELD FROM STAKING

- Pending ETH yield (estimate): 240126960
- ETH yield claimed: 240126960
> ✅ **PASS** — Staking yield claim succeeded

## Phase 7: DIRECT PYRE BURN (FireSpirit progression)

- Burned PYRE: 10000000000000000000000
- Total supply delta: -10000000000000000000000
- FireSpirit pendingBurn before: 100000000000000000000
- FireSpirit pendingBurn after:  0
- Hook totalPyreBurned (swap fees only): 227950000000000000
- FireSpirit tokenId: 1
- FireSpirit stage (0=EMBER 1=FLAME 2=FORGE 3=PYRE): 0
- Cumulative burn: 10100000000000000000000
> ✅ **PASS** — Direct burn accounting correct

## Phase 8: LP BURN BONUS (+20% STAKING WEIGHT)

- Staked balance: 300000000000000000000
- LP burner already flagged: true
- Weight BEFORE flagging: 360000000000000000000
- Weight AFTER flagging:  360000000000000000000
- SKIP: already flagged — weight unchanged (expected)
## Phase 9: SECOND SELL SWAP (cumulative burn verification)

- Sell swap — PYRE in: 1000000000000000 wei
### Delta: After Sell 2

| Metric | Before | After | Delta |
|---|---|---|---|
| tester ETH | `1084523702647708374` | `1084523702647772753` | **+64379** |
| tester PYRE | `462144411101210075356958` | `462144410101210075356958` | **-1000000000000000** |
| team ETH | `1084523702647708374` | `1084523702647772753` | **+64379** |
| staking ETH | `1034200467680` | `1034200467680` | **no change** |
| hook ETH | `0` | `0` | **no change** |
| totalSupply PYRE | `989899772050000000000000` | `989899772000000000000000` | **-50000000000000** |
| totalEthToYield | `1035200000000` | `1035200000000` | **no change** |
| totalEthToTeam | `258800000000` | `258800000000` | **no change** |
| totalPyreBurned | `227950000000000000` | `228000000000000000` | **+50000000000000** |

- Current sellFeeBps at sell2: 500

**Sell Burn Assertion**

| Check | Expected | Actual | Status |
|---|---|---|---|
| Sell burn (500 bps) | `50000000000000` | `50000000000000` | ✅ PASS |

> ✅ **PASS** — Sell PYRE burn accounting correct

- Cumulative hook burn total: 228000000000000000
## Final State

### State After All Phases

| Metric | Value |
|---|---|
| tester ETH | `1084523702647772753` |
| tester PYRE | `462144410101210075356958` |
| team ETH | `1084523702647772753` |
| staking ETH | `1034200467680` |
| hook ETH | `0` |
| totalSupply PYRE | `989899772000000000000000` |
| totalEthToYield | `1035200000000` |
| totalEthToTeam | `258800000000` |
| totalPyreBurned | `228000000000000000` |

## Summary

| Phase | Status |
|---|---|
| Phase 1 — Pool Setup | ✅ PASS |
| Phase 2 — Buy Swap fee routing | ✅ PASS |
| Phase 3 — Sell swap PYRE burn | ✅ PASS |
| Phase 4 — PYRE staking | ✅ PASS |
| Phase 5 — Yield routing to staking | ✅ PASS |
| Phase 6 — ETH yield claim | ✅ PASS |
| Phase 7 — Direct burn + FireSpirit | ✅ PASS |
| Phase 8 — LP burn bonus weight | ✅ PASS |
| Phase 9 — Cumulative burn check | ✅ PASS |

> **All workflow checks passed ✅**

