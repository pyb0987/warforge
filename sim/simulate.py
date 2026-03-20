#!/usr/bin/env python3
"""Chain Army balance simulator.

⚠ DEPRECATED: 이 시뮬레이터는 초기 프로토타입(Iteration 3) 기준입니다.
DESIGN.md에 확정된 2층 카드 아키텍처, 2화폐 경제(골드+테라진),
SC1 스타일 전투 시스템(AS/Range/MS), 6단계 상점 레벨업 등이 미반영되어
새로운 시뮬레이터로 교체가 필요합니다.
최신 게임 설계는 DESIGN.md를 참조하세요.

Usage:
    python sim/simulate.py                         # 200 runs, 물량배양
    python sim/simulate.py -s 정예강화             # different strategy
    python sim/simulate.py -n 50 -v                # verbose last run
    python sim/simulate.py --seed 42               # reproducible

Tune parameters in the CONFIG section to iterate on balance.
"""

import argparse
import random
import math
from collections import deque, defaultdict

# ════════════════════════════════════════════════════════════
# CONFIG — Edit these to test balance
# ════════════════════════════════════════════════════════════

STARTING_GOLD = 13
BASE_INCOME = 4
KILL_BONUS_MAX = 5
CARD_COST = 3
REROLL_COST = 1
SELL_LOSS = 1          # sell price = cost - SELL_LOSS (min 1)

SHOP_SIZE = 5          # cards shown per shop
CARD_POOL_SIZE = 15    # total unique cards

FIELD_SLOTS = {
    1: 4, 2: 4, 3: 4, 4: 4,
    5: 5, 6: 5, 7: 5,
    8: 6, 9: 6, 10: 6,
    11: 7, 12: 7, 13: 7, 14: 7, 15: 7,
}

PLAYER_HP = 30
TOTAL_ROUNDS = 15
BOSS_ROUNDS = {4, 8, 12, 15}

HP_SCALE = 1           # combat_hp = base_hp * HP_SCALE
MAX_TICKS = 120        # combat timeout
UNIT_CAP = 40          # max units per card (0 = unlimited)

# ════════════════════════════════════════════════════════════
# CARD DEFINITIONS
# u=units, a=atk, h=hp, lim=activation limit
# trig: None | round_start | on_cultivate | on_adj_cultivate
#       | on_enhance | on_purchase | on_merge | on_battle_loss
# eff.act: cultivate | enhance | cult_enh
# eff.tgt: right_adj | self | event_target | both_adj
# eff.cu=cultivate count, ea=enhance atk, eh=enhance hp
# ════════════════════════════════════════════════════════════

CARDS = {
    "양성사": {
        1: dict(u=1, a=1, h=35, lim=2, trig="round_start",
                eff=dict(act="cultivate", tgt="right_adj", cu=1)),
        2: dict(u=1, a=2, h=50, lim=3, trig="round_start",
                eff=dict(act="cultivate", tgt="right_adj", cu=1)),
        3: dict(u=2, a=3, h=65, lim=5, trig="round_start",
                eff=dict(act="cult_enh", tgt="right_adj", cu=2, ea=1, eh=1)),
    },
    "배양소": {
        1: dict(u=2, a=1, h=25, lim=2, trig="on_adj_cultivate",
                eff=dict(act="cultivate", tgt="self", cu=1)),
        2: dict(u=3, a=1, h=35, lim=3, trig="on_adj_cultivate",
                eff=dict(act="cultivate", tgt="self", cu=1)),
        3: dict(u=4, a=2, h=45, lim=4, trig="on_adj_cultivate",
                eff=dict(act="cultivate", tgt="self", cu=1)),
    },
    "훈련교관": {
        1: dict(u=1, a=2, h=35, lim=3, trig="on_cultivate",
                eff=dict(act="enhance", tgt="event_target", ea=1, eh=1)),
        2: dict(u=1, a=3, h=45, lim=4, trig="on_cultivate",
                eff=dict(act="enhance", tgt="event_target", ea=1, eh=1)),
        3: dict(u=2, a=3, h=55, lim=5, trig="on_cultivate",
                eff=dict(act="enhance", tgt="event_target", ea=2, eh=2)),
    },
    "결집의깃발": {
        1: dict(u=1, a=0, h=25, lim=2, trig="on_enhance",
                eff=dict(act="enhance", tgt="both_adj", ea=0, eh=3)),
        2: dict(u=1, a=0, h=35, lim=3, trig="on_enhance",
                eff=dict(act="enhance", tgt="both_adj", ea=0, eh=3)),
        3: dict(u=2, a=1, h=45, lim=4, trig="on_enhance",
                eff=dict(act="enhance", tgt="both_adj", ea=0, eh=5)),
    },
    "대장장이": {
        1: dict(u=1, a=1, h=40, lim=2, trig="on_enhance",
                eff=dict(act="enhance", tgt="event_target", ea=1, eh=0)),
        2: dict(u=1, a=2, h=50, lim=3, trig="on_enhance",
                eff=dict(act="enhance", tgt="event_target", ea=1, eh=0)),
        3: dict(u=2, a=2, h=60, lim=4, trig="on_enhance",
                eff=dict(act="enhance", tgt="event_target", ea=2, eh=0)),
    },
    "군수관": {
        1: dict(u=1, a=0, h=35, lim=1, trig="on_purchase",
                eff=dict(act="enhance", tgt="event_target", ea=1, eh=1)),
        2: dict(u=1, a=1, h=45, lim=2, trig="on_purchase",
                eff=dict(act="enhance", tgt="event_target", ea=1, eh=1)),
        3: dict(u=2, a=1, h=55, lim=3, trig="on_purchase",
                eff=dict(act="enhance", tgt="event_target", ea=2, eh=1)),
    },
    "전쟁고아": {
        1: dict(u=3, a=2, h=20, lim=1, trig="on_battle_loss",
                eff=dict(act="cultivate", tgt="self", cu=2)),
        2: dict(u=4, a=2, h=25, lim=1, trig="on_battle_loss",
                eff=dict(act="cultivate", tgt="self", cu=3)),
        3: dict(u=5, a=3, h=35, lim=2, trig="on_battle_loss",
                eff=dict(act="cult_enh", tgt="self", cu=3, ea=1, eh=1)),
    },
    "사관학교": {
        1: dict(u=2, a=2, h=25, lim=1, trig="on_merge",
                eff=dict(act="cultivate", tgt="event_target", cu=2)),
        2: dict(u=2, a=3, h=35, lim=2, trig="on_merge",
                eff=dict(act="cultivate", tgt="event_target", cu=2)),
        3: dict(u=3, a=3, h=45, lim=3, trig="on_merge",
                eff=dict(act="cult_enh", tgt="event_target", cu=3, ea=1, eh=0)),
    },
    "돌격부대": {
        1: dict(u=5, a=2, h=30, lim=0, trig=None, eff=None),
        2: dict(u=7, a=3, h=40, lim=0, trig=None, eff=None),
        3: dict(u=10, a=4, h=50, lim=0, trig=None, eff=None),
    },
    "방패병분대": {
        1: dict(u=4, a=1, h=50, lim=0, trig=None, eff=None),
        2: dict(u=5, a=2, h=70, lim=0, trig=None, eff=None),
        3: dict(u=7, a=3, h=90, lim=0, trig=None, eff=None),
    },
    "정예기사": {
        1: dict(u=2, a=5, h=45, lim=0, trig=None, eff=None),
        2: dict(u=3, a=6, h=60, lim=0, trig=None, eff=None),
        3: dict(u=4, a=8, h=80, lim=0, trig=None, eff=None),
    },
    "척후병": {
        1: dict(u=3, a=3, h=20, lim=0, trig=None, eff=None),
        2: dict(u=4, a=4, h=25, lim=0, trig=None, eff=None),
        3: dict(u=5, a=5, h=35, lim=0, trig=None, eff=None),
    },
    "광전사무리": {
        1: dict(u=3, a=4, h=20, lim=0, trig=None, eff=None),
        2: dict(u=5, a=5, h=25, lim=0, trig=None, eff=None),
        3: dict(u=8, a=6, h=35, lim=0, trig=None, eff=None),
    },
    "사령술사": {
        1: dict(u=1, a=1, h=45, lim=0, trig=None, eff=None),
        2: dict(u=1, a=2, h=60, lim=0, trig=None, eff=None),
        3: dict(u=2, a=3, h=70, lim=0, trig=None, eff=None),
    },
    "전쟁드럼": {
        1: dict(u=1, a=0, h=35, lim=0, trig=None, eff=None),
        2: dict(u=1, a=1, h=45, lim=0, trig=None, eff=None),
        3: dict(u=2, a=1, h=55, lim=0, trig=None, eff=None),
    },
}

CARD_POOL = list(CARDS.keys())

# ════════════════════════════════════════════════════════════
# ENEMY TABLE — (units, atk, hp)
# ════════════════════════════════════════════════════════════

ENEMIES = {
    1:  (6,  1,  15),
    2:  (8,  2,  22),
    3:  (10, 3,  30),
    4:  (13, 4,  40),
    5:  (24, 7,  58),     # boss
    6:  (24, 8,  68),
    7:  (27, 10, 82),
    8:  (30, 13, 100),
    9:  (34, 16, 125),
    10: (40, 22, 160),    # boss
    11: (44, 26, 190),
    12: (48, 30, 210),
    13: (52, 34, 230),
    14: (55, 38, 250),
    15: (58, 42, 270),    # boss
}

# ════════════════════════════════════════════════════════════
# BUILD STRATEGIES (for AI)
# ════════════════════════════════════════════════════════════

STRATEGIES = {
    "물량배양": dict(
        core=["양성사", "돌격부대", "배양소", "훈련교관"],
        expand=["대장장이", "결집의깃발", "전쟁고아"],
        upgrade_prio=["양성사", "돌격부대"],
        board_order=["양성사", "돌격부대", "배양소", "훈련교관",
                     "대장장이", "결집의깃발", "전쟁고아"],
    ),
    "정예강화": dict(
        core=["양성사", "정예기사", "훈련교관", "대장장이"],
        expand=["결집의깃발", "군수관", "방패병분대"],
        upgrade_prio=["양성사", "정예기사"],
        board_order=["양성사", "정예기사", "훈련교관", "대장장이",
                     "결집의깃발", "군수관", "방패병분대"],
    ),
}

# ════════════════════════════════════════════════════════════
# CARD CLASS
# ════════════════════════════════════════════════════════════

class Card:
    def __init__(self, name, star=1):
        self.name = name
        self.star = star
        d = CARDS[name][star]
        self.base_units = d["u"]
        self.base_atk = d["a"]
        self.base_hp = d["h"]
        self.bonus_units = 0
        self.bonus_atk = 0
        self.bonus_hp = 0
        self.acts_left = 0

    @property
    def units(self):
        u = self.base_units + self.bonus_units
        return min(u, UNIT_CAP) if UNIT_CAP > 0 else u

    @property
    def atk(self):
        return self.base_atk + self.bonus_atk

    @property
    def hp(self):
        return self.base_hp + self.bonus_hp

    @property
    def total_atk(self):
        return self.units * self.atk

    @property
    def total_hp(self):
        return self.units * self.hp

    @property
    def combat_power(self):
        return self.units * self.atk * self.hp

    def get_def(self):
        return CARDS[self.name][self.star]

    def cultivate(self, count):
        self.bonus_units += count

    def enhance(self, da, dh):
        self.bonus_atk += da
        self.bonus_hp += dh

    def upgrade_star(self):
        self.star += 1
        d = CARDS[self.name][self.star]
        self.base_units = d["u"]
        self.base_atk = d["a"]
        self.base_hp = d["h"]

    def __repr__(self):
        return f"{self.name}★{self.star}({self.units}u {self.atk}/{self.hp})"

# ════════════════════════════════════════════════════════════
# GROWTH CHAIN ENGINE
# ════════════════════════════════════════════════════════════

def _resolve_targets(tgt_type, card_idx, evt_target_idx, board_len):
    if tgt_type == "right_adj":
        r = card_idx + 1
        if r < board_len:
            return [r]
        elif card_idx > 0:
            return [card_idx - 1]
        return []
    elif tgt_type == "self":
        return [card_idx]
    elif tgt_type == "event_target":
        return [evt_target_idx] if evt_target_idx is not None else []
    elif tgt_type == "both_adj":
        result = []
        if card_idx > 0:
            result.append(card_idx - 1)
        if card_idx + 1 < board_len:
            result.append(card_idx + 1)
        return result
    return []


def _apply_effect(card_idx, eff, evt_target_idx, board):
    if not eff:
        return []
    targets = _resolve_targets(eff["tgt"], card_idx, evt_target_idx, len(board))
    events = []
    for ti in targets:
        tgt = board[ti]
        act = eff["act"]
        if act in ("cultivate", "cult_enh"):
            tgt.cultivate(eff.get("cu", 0))
            events.append(("cultivate", ti))
        if act in ("enhance", "cult_enh"):
            ea, eh = eff.get("ea", 0), eff.get("eh", 0)
            tgt.enhance(ea, eh)
            if ea > 0 or eh > 0:
                events.append(("enhance", ti))
    return events


def _matches_trigger(trig, evt_type, evt_target_idx, card_idx):
    if trig == "on_cultivate":
        return evt_type == "cultivate"
    elif trig == "on_adj_cultivate":
        return evt_type == "cultivate" and abs(evt_target_idx - card_idx) == 1
    elif trig == "on_enhance":
        return evt_type == "enhance"
    return False


def resolve_growth_chain(board):
    """Resolve round-start growth chain. Returns chain count."""
    if not board:
        return 0

    for card in board:
        card.acts_left = card.get_def()["lim"]

    queue = deque()
    chains = 0

    # Round-start triggers fire N times (N = activation limit)
    for i, card in enumerate(board):
        d = card.get_def()
        if d["trig"] == "round_start":
            fires = card.acts_left
            card.acts_left = 0
            for _ in range(fires):
                evts = _apply_effect(i, d["eff"], None, board)
                queue.extend(evts)
                chains += 1

    # Event cascade (BFS, left-to-right scan)
    while queue:
        evt_type, evt_target_idx = queue.popleft()
        for i, card in enumerate(board):
            d = card.get_def()
            if not d["trig"] or card.acts_left <= 0:
                continue
            if _matches_trigger(d["trig"], evt_type, evt_target_idx, i):
                card.acts_left -= 1
                evts = _apply_effect(i, d["eff"], evt_target_idx, board)
                queue.extend(evts)
                chains += 1

    return chains

# ════════════════════════════════════════════════════════════
# COMBAT ENGINE
# ════════════════════════════════════════════════════════════

def simulate_combat(board, enemy_def, rng):
    """Tick-based combat with random targeting.
    Returns (won: bool, enemy_survivors: int).
    """
    player = []
    for card in board:
        for _ in range(card.units):
            player.append([card.hp * HP_SCALE, card.atk])

    eu, ea, eh = enemy_def
    enemy = [[eh * HP_SCALE, ea] for _ in range(eu)]

    for _ in range(MAX_TICKS):
        if not player or not enemy:
            break

        # Player attacks
        for u in player:
            if u[1] > 0 and enemy:
                t = rng.randrange(len(enemy))
                enemy[t][0] -= u[1]
        enemy = [u for u in enemy if u[0] > 0]
        if not enemy:
            break

        # Enemy attacks
        for u in enemy:
            if u[1] > 0 and player:
                t = rng.randrange(len(player))
                player[t][0] -= u[1]
        player = [u for u in player if u[0] > 0]

    return (True, 0) if not enemy else (False, len(enemy))

# ════════════════════════════════════════════════════════════
# RUN SIMULATOR
# ════════════════════════════════════════════════════════════

class RunSimulator:
    def __init__(self, strategy_name, rng):
        self.strat = STRATEGIES[strategy_name]
        self.rng = rng
        self.board = []
        self.hand = []
        self.gold = STARTING_GOLD
        self.hp = PLAYER_HP
        self.star_upgrades = {}  # card_name -> (round_achieved, star)

    def run(self, verbose=False):
        results = []
        for rnd in range(1, TOTAL_ROUNDS + 1):
            if self.hp <= 0:
                break
            r = self._play_round(rnd)
            results.append(r)
            if verbose:
                self._print_round(r)
        return results

    def _play_round(self, rnd):
        self._shop_phase(rnd)
        self._merge_phase(rnd)
        self._arrange_board(rnd)

        chains = resolve_growth_chain(self.board)

        total_atk = sum(c.total_atk for c in self.board)
        total_hp = sum(c.total_hp for c in self.board)
        total_units = sum(c.units for c in self.board)

        enemy = ENEMIES[rnd]
        won, survivors = simulate_combat(self.board, enemy, self.rng)

        if not won:
            self.hp -= survivors
            self._battle_loss_triggers()

        kills = enemy[0] - survivors
        self.gold += BASE_INCOME + min(max(kills, 0), KILL_BONUS_MAX)

        return dict(
            round=rnd, chains=chains,
            total_atk=total_atk, total_hp=total_hp,
            total_units=total_units, won=won,
            damage=0 if won else survivors, hp=self.hp,
            gold=self.gold,
            board_str=" | ".join(repr(c) for c in self.board),
            stars={c.name: c.star for c in self.board + self.hand},
        )

    def _shop_phase(self, rnd):
        offers = self.rng.choices(CARD_POOL, k=SHOP_SIZE)
        rerolls = 0
        max_rerolls = 3 if self.gold > 8 else 2

        while self.gold >= CARD_COST:
            wanted = self._wanted_cards()
            buy_name = None
            for name in (self.strat["upgrade_prio"] + self.strat["core"]
                         + self.strat["expand"]):
                if name in offers and name in wanted:
                    buy_name = name
                    break
            if buy_name:
                card = Card(buy_name)
                self._on_purchase(card)
                self.hand.append(card)
                self.gold -= CARD_COST
                offers.remove(buy_name)
            elif rerolls < max_rerolls and self.gold >= REROLL_COST + CARD_COST:
                offers = self.rng.choices(CARD_POOL, k=SHOP_SIZE)
                self.gold -= REROLL_COST
                rerolls += 1
            else:
                break

    def _on_purchase(self, purchased_card):
        for card in self.board:
            d = card.get_def()
            if d["trig"] == "on_purchase" and d["eff"]:
                for _ in range(d["lim"]):
                    eff = d["eff"]
                    purchased_card.enhance(eff.get("ea", 0), eff.get("eh", 0))

    def _wanted_cards(self):
        wanted = set()
        all_cards = self.board + self.hand
        for name in self.strat["core"]:
            if not any(c.name == name for c in self.board):
                wanted.add(name)
        for name in self.strat["upgrade_prio"]:
            max_star = max((c.star for c in all_cards if c.name == name), default=0)
            if max_star < 3:
                wanted.add(name)
        slots = FIELD_SLOTS.get(len(self.board) + 1, 7)
        if len(self.board) < slots:
            for name in self.strat["expand"]:
                if not any(c.name == name for c in all_cards):
                    wanted.add(name)
        return wanted

    def _merge_phase(self, rnd):
        while True:
            all_cards = self.board + self.hand
            groups = defaultdict(list)
            for c in all_cards:
                groups[(c.name, c.star)].append(c)

            merged = False
            for (name, star), cards in groups.items():
                if len(cards) >= 3 and star < 3:
                    keep = cards[0]
                    for c in cards[1:3]:
                        if c in self.board:
                            self.board.remove(c)
                        elif c in self.hand:
                            self.hand.remove(c)
                    keep.upgrade_star()
                    self.star_upgrades[name] = (rnd, keep.star)
                    self._on_merge(keep)
                    merged = True
                    break
            if not merged:
                break

    def _on_merge(self, merged_card):
        for card in self.board:
            d = card.get_def()
            if d["trig"] == "on_merge" and d["eff"]:
                for _ in range(d["lim"]):
                    eff = d["eff"]
                    if eff["act"] in ("cultivate", "cult_enh"):
                        merged_card.cultivate(eff.get("cu", 0))
                    if eff["act"] in ("enhance", "cult_enh"):
                        merged_card.enhance(eff.get("ea", 0), eff.get("eh", 0))

    def _battle_loss_triggers(self):
        for card in self.board:
            d = card.get_def()
            if d["trig"] == "on_battle_loss" and d["eff"]:
                eff = d["eff"]
                for _ in range(d["lim"]):
                    if eff["act"] in ("cultivate", "cult_enh"):
                        card.cultivate(eff.get("cu", 0))
                    if eff["act"] in ("enhance", "cult_enh"):
                        card.enhance(eff.get("ea", 0), eff.get("eh", 0))

    def _arrange_board(self, rnd):
        max_slots = FIELD_SLOTS.get(rnd, 7)
        all_cards = self.board + self.hand
        self.board = []
        self.hand = []
        placed = set()

        for name in self.strat["board_order"]:
            cands = [c for c in all_cards
                     if c.name == name and id(c) not in placed]
            if cands and len(self.board) < max_slots:
                best = max(cands, key=lambda c: (c.star, c.combat_power))
                self.board.append(best)
                placed.add(id(best))

        remaining = sorted(
            [c for c in all_cards if id(c) not in placed],
            key=lambda c: c.combat_power, reverse=True)
        for c in remaining:
            if len(self.board) < max_slots:
                self.board.append(c)
                placed.add(id(c))
            else:
                self.hand.append(c)

    @staticmethod
    def _print_round(r):
        status = "WIN" if r["won"] else f"LOSE(-{r['damage']}hp)"
        print(f"  R{r['round']:2d} | {status:12s} | "
              f"chain:{r['chains']:3d} | "
              f"ATK:{r['total_atk']:6d} HP:{r['total_hp']:6d} | "
              f"units:{r['total_units']:3d} | "
              f"hp:{r['hp']:3d} gold:{r['gold']:3d}")
        print(f"       {r['board_str']}")

# ════════════════════════════════════════════════════════════
# BATCH RUNNER & OUTPUT
# ════════════════════════════════════════════════════════════

def run_batch(strategy_name, num_runs, base_seed=None, verbose=False):
    all_runs = []

    for i in range(num_runs):
        seed = (base_seed + i) if base_seed is not None else None
        rng = random.Random(seed)
        sim = RunSimulator(strategy_name, rng)
        show = verbose and (i == num_runs - 1)
        if show:
            print(f"\n{'='*60}")
            print(f"  Sample Run #{i+1} (verbose)")
            print(f"{'='*60}")
        result = sim.run(verbose=show)
        all_runs.append(result)

    print_summary(strategy_name, all_runs, num_runs)


def print_summary(strategy_name, all_runs, num_runs):
    print(f"\n{'='*70}")
    print(f"  Balance Report: {num_runs} runs, \"{strategy_name}\"")
    print(f"{'='*70}")

    # Per-round stats
    round_stats = defaultdict(lambda: dict(
        wins=0, total=0, chains=[], atk=[], hp=[], units=[],
        player_hp=[], damage=[]))

    clears = 0
    final_rounds = []

    for run in all_runs:
        last_round = run[-1]["round"] if run else 0
        alive = run[-1]["hp"] > 0 if run else False
        if alive and last_round == TOTAL_ROUNDS:
            clears += 1
        final_rounds.append(last_round)

        for r in run:
            rs = round_stats[r["round"]]
            rs["total"] += 1
            rs["wins"] += 1 if r["won"] else 0
            rs["chains"].append(r["chains"])
            rs["atk"].append(r["total_atk"])
            rs["hp"].append(r["total_hp"])
            rs["units"].append(r["total_units"])
            rs["player_hp"].append(r["hp"])
            rs["damage"].append(r["damage"])

    # Enemy power for reference
    def enemy_power(rnd):
        eu, ea, eh = ENEMIES[rnd]
        return eu * ea * eh

    print(f"\n  R  | Win%  | Chain | Player ATK | Player HP | Units "
          f"| Enemy Pwr | Avg Dmg | Avg HP")
    print(f"  ---|-------|-------|------------|-----------|-------"
          f"|-----------|---------|-------")

    for rnd in range(1, TOTAL_ROUNDS + 1):
        rs = round_stats[rnd]
        if rs["total"] == 0:
            continue
        wr = rs["wins"] / rs["total"] * 100
        avg = lambda lst: sum(lst) / len(lst) if lst else 0
        boss = " *" if rnd in BOSS_ROUNDS else "  "
        ep = enemy_power(rnd)
        print(f"  {rnd:2d}{boss}| {wr:4.0f}% | {avg(rs['chains']):5.1f} | "
              f"{avg(rs['atk']):10.0f} | {avg(rs['hp']):9.0f} | "
              f"{avg(rs['units']):5.0f} | {ep:9d} | "
              f"{avg(rs['damage']):7.1f} | {avg(rs['player_hp']):5.1f}")

    # ★ upgrade stats
    print(f"\n  * = boss round")

    avg_final = sum(final_rounds) / len(final_rounds)
    clear_rate = clears / num_runs * 100
    print(f"\n  Clear rate:     {clear_rate:.1f}% ({clears}/{num_runs})")
    print(f"  Avg round:      {avg_final:.1f}")

    # Balance alerts
    print(f"\n  Balance Alerts:")
    alerts = 0
    for rnd in range(1, TOTAL_ROUNDS + 1):
        rs = round_stats[rnd]
        if rs["total"] == 0:
            continue
        wr = rs["wins"] / rs["total"] * 100

        if rnd <= 3 and wr < 90:
            print(f"    ! R{rnd} win rate {wr:.0f}% too low"
                  f" (early game should be >90%)")
            alerts += 1
        elif rnd in BOSS_ROUNDS and wr > 80:
            print(f"    ! R{rnd} boss win rate {wr:.0f}% too high"
                  f" (boss should be 40-70%)")
            alerts += 1
        elif rnd in BOSS_ROUNDS and wr < 20:
            print(f"    ! R{rnd} boss win rate {wr:.0f}% too low"
                  f" (boss should be 40-70%)")
            alerts += 1
        elif rnd >= 12 and wr > 70:
            print(f"    ! R{rnd} win rate {wr:.0f}% too high"
                  f" (late game should challenge ★3 builds)")
            alerts += 1

    if clear_rate > 60:
        print(f"    ! Clear rate {clear_rate:.0f}% too high"
              f" (target 20-40%)")
        alerts += 1
    elif clear_rate < 10:
        print(f"    ! Clear rate {clear_rate:.0f}% too low"
              f" (target 20-40%)")
        alerts += 1

    if alerts == 0:
        print(f"    None — balance looks reasonable.")

    print()

# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════

def main():
    p = argparse.ArgumentParser(description="Chain Army balance simulator")
    p.add_argument("-s", "--strategy", default="물량배양",
                   choices=list(STRATEGIES.keys()))
    p.add_argument("-n", "--runs", type=int, default=200)
    p.add_argument("-v", "--verbose", action="store_true",
                   help="Show last run in detail")
    p.add_argument("--seed", type=int, default=None)
    args = p.parse_args()

    run_batch(args.strategy, args.runs, args.seed, args.verbose)


if __name__ == "__main__":
    main()
