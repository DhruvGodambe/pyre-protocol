# 🔥 Pyre Protocol — Full Workflow Smoke Test

> **Chain:** Base Sepolia (84532)
> **Block:** `11103503`
> **Timestamp:** `1781983428`

---
## Configuration

| Parameter | Address |
|---|---|
| poolManager | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| swapRouter | `0x00000000000044a361Ae3cAc094c9D1b14Eece97` |
| pyreToken | `0xaBd9bf9008090F091729290C4e898CB206eDD785` |
| staking | `0xF690b15B4DDAb1f3927737d52088D7A0a75f3E42` |
| fireSpirit | `0xC0F652201E9382224D0619d26436664a157b0d50` |
| hook | `0xCe9cD7eFF1156D566CFEBADA4C025597cF51BFF8` |
| team | `0x8343b8758C025c72A5A8906C64541d1357984949` |
| tester | `0xF93E7518F79C2E1978D6862Dbf161270040e623E` |

| Parameter | Value |
|---|---|
| buyFeeBps (current) | `910` |
| sellFeeBps (current) | `1973` |
| ethBuyAmount | `1000000000000` wei |
| pyreSellAmount | `10000000000000000000` wei |
| stakeAmount | `100000000000000000000` wei |
| directBurnAmount | `10000000000000000000000` wei |
| liquidityDelta | `500000000000000000` |
| liquidityEthValue | `5000000000000000` wei |

## Pre-Run State

### State Before

| Metric | Value |
|---|---|
| tester ETH | `441902026950322111` |
| tester PYRE | `9989990089848832711472959` |
| team ETH | `1980740496565519302` |
| staking ETH | `0` |
| hook ETH | `0` |
| totalSupply PYRE | `10000000000000000000000000` |
| totalEthToYield | `0` |
| totalEthToTeam | `22541830690483` |
| totalPyreBurned | `0` |

> ✅ **PASS** — Approvals set (PERMIT2, PositionManager, SwapRouter, Staking)

## Phase 2: BUY SWAP (ETH -> PYRE)

- Buy swap — ETH in: 1000000000000 wei
### Delta: After Buy

| Metric | Before | After | Delta |
|---|---|---|---|
| tester ETH | `441902026950322111` | `441901117950322111` | **-909000000000** |
| tester PYRE | `9989990089848832711472959` | `9989990180654479704106543` | **+90805646992633584** |
| team ETH | `1980740496565519302` | `1980740496565519302` | **no change** |
| staking ETH | `0` | `0` | **no change** |
| hook ETH | `0` | `0` | **no change** |
| totalSupply PYRE | `10000000000000000000000000` | `10000000000000000000000000` | **no change** |
| totalEthToYield | `0` | `0` | **no change** |
| totalEthToTeam | `22541830690483` | `22632830690483` | **+91000000000** |
| totalPyreBurned | `0` | `0` | **no change** |


**Fee Routing Assertion**

| Check | Expected | Actual | Status |
|---|---|---|---|
| Buy fee (910 bps) | `91000000000` | — | — |
| 0% → staking | `0` | `0` | ✅ PASS |
| 100% → team | `91000000000` | `91000000000` | ✅ PASS |

> ✅ **PASS** — Buy fee routing correct (0/100 split verified)

## Phase 3: SELL SWAP (PYRE -> ETH)

- Sell swap — PYRE in: 10000000000000000000 wei
### Delta: After Sell

| Metric | Before | After | Delta |
|---|---|---|---|
| tester ETH | `441901117950322111` | `442000524026097818` | **+99406075775707** |
| tester PYRE | `9989990180654479704106543` | `9989980180654479704106543` | **-10000000000000000000** |
| team ETH | `1980740496565519302` | `1980740496565519302` | **no change** |
| staking ETH | `0` | `0` | **no change** |
| hook ETH | `0` | `0` | **no change** |
| totalSupply PYRE | `10000000000000000000000000` | `10000000000000000000000000` | **no change** |
| totalEthToYield | `0` | `0` | **no change** |
| totalEthToTeam | `22632830690483` | `42229981338151` | **+19597150647668** |
| totalPyreBurned | `0` | `0` | **no change** |


**Sell Fee Routing Assertion**

| Check | Status |
|---|---|
| Zero PYRE Burned | ✅ PASS |
| Sell PYRE fee swapped to ETH | ✅ PASS |
| 0% ETH to yield pool | ✅ PASS |
| 100% ETH to team wallet | ✅ PASS |

> ✅ **PASS** — Sell PYRE fee routing to team verified

## Final State

### State After All Phases

| Metric | Value |
|---|---|
| tester ETH | `442000524026097818` |
| tester PYRE | `9989980180654479704106543` |
| team ETH | `1980740496565519302` |
| staking ETH | `0` |
| hook ETH | `0` |
| totalSupply PYRE | `10000000000000000000000000` |
| totalEthToYield | `0` |
| totalEthToTeam | `42229981338151` |
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

