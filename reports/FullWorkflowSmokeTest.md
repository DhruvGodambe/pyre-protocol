# 🔥 Pyre Protocol — Full Workflow Smoke Test

> **Chain:** Base Sepolia (84532)
> **Block:** `11089723`
> **Timestamp:** `1781817600`

---
## Configuration

| Parameter | Address |
|---|---|
| poolManager | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| swapRouter | `0x00000000000044a361Ae3cAc094c9D1b14Eece97` |
| pyreToken | `0x8999Eac3Df09a3f46099130a56c5CB1e9D79bA2a` |
| staking | `0x55C6aeDC9d5384F00aEcd3515556A150e272168B` |
| fireSpirit | `0x66e59002c557ec646dd81A9451f19a0332c61d0d` |
| hook | `0x9952d25eDA1f305fcDb6Ca9029520e33A7263Ff8` |
| team | `0xF93E7518F79C2E1978D6862Dbf161270040e623E` |
| tester | `0xF93E7518F79C2E1978D6862Dbf161270040e623E` |

| Parameter | Value |
|---|---|
| buyFeeBps (current) | `953` |
| sellFeeBps (current) | `2130` |
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
| tester ETH | `674866257347936792` |
| tester PYRE | `9934461759632046048803444` |
| team ETH | `674866257347936792` |
| staking ETH | `624036379091` |
| hook ETH | `0` |
| totalSupply PYRE | `9990000000000000000000000` |
| totalEthToYield | `624940396591` |
| totalEthToTeam | `156235099148` |
| totalPyreBurned | `0` |

> ✅ **PASS** — Approvals set (PERMIT2, PositionManager, SwapRouter, Staking)

## Phase 7: DIRECT PYRE BURN (FireSpirit progression)

- Burned PYRE: 10000000000000000000000
- Total supply delta: -10000000000000000000000
- FireSpirit pendingBurn before: 0
- FireSpirit pendingBurn after:  0
- Hook totalPyreBurned (swap fees only): 0
- FireSpirit tokenId: 1
- FireSpirit stage (0=EMBER 1=FLAME 2=FORGE 3=PYRE): 0
- Cumulative burn: 20000000000000000000000
> ✅ **PASS** — Direct burn accounting correct

## Phase 8: LP BURN BONUS (+20% STAKING WEIGHT)

- Staked balance: 400000000000000000000
- LP burner already flagged: false
- Weight BEFORE flagging: 400000000000000000000
- Weight AFTER flagging:  480000000000000000000
- Expected weight (x1.2): 480000000000000000000

| Metric | Value |
|---|---|
| Weight before | `400000000000000000000` |
| Weight after  | `480000000000000000000` |
| Expected (x1.2) | `480000000000000000000` |
| Delta | `+80000000000000000000` |

> ✅ **PASS** — LP burn bonus: staking weight increased by exactly 20%

## Phase 9: SECOND SELL SWAP (cumulative burn verification)

- Sell swap — PYRE in: 1000000000000000 wei
### Delta: After Sell 2

| Metric | Before | After | Delta |
|---|---|---|---|
| tester ETH | `674866257533662392` | `674866265805914423` | **+8272252031** |
| tester PYRE | `9924461759632046048803444` | `9924461758632046048803444` | **-1000000000000000** |
| team ETH | `674866257533662392` | `674866265805914423` | **+8272252031** |
| staking ETH | `623850653491` | `625549775502` | **+1699122011** |
| hook ETH | `0` | `0` | **no change** |
| totalSupply PYRE | `9980000000000000000000000` | `9980000000000000000000000` | **no change** |
| totalEthToYield | `624940396591` | `626639518602` | **+1699122011** |
| totalEthToTeam | `156235099148` | `156659879651` | **+424780503** |
| totalPyreBurned | `0` | `0` | **no change** |

- Current sellFeeBps at sell2: 2130

**Sell Fee Routing Assertion**

| Check | Status |
|---|---|
| Zero PYRE Burned | ✅ PASS |
| Sell PYRE fee swapped to ETH | ✅ PASS |
| 80% ETH to yield pool | ✅ PASS |
| 20% ETH to team wallet | ✅ PASS |

> ✅ **PASS** — Sell PYRE fee routing to ETH yield pool and team verified

- Cumulative hook burn total: 0
## Final State

### State After All Phases

| Metric | Value |
|---|---|
| tester ETH | `674866265805914423` |
| tester PYRE | `9924461758632046048803444` |
| team ETH | `674866265805914423` |
| staking ETH | `625549775502` |
| hook ETH | `0` |
| totalSupply PYRE | `9980000000000000000000000` |
| totalEthToYield | `626639518602` |
| totalEthToTeam | `156659879651` |
| totalPyreBurned | `0` |

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

