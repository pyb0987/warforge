"""UnitType registry."""

from .types import UnitType

_REGISTRY: dict[str, UnitType] = {}


def register(unit: UnitType) -> None:
    _REGISTRY[unit.id] = unit


def get(unit_id: str) -> UnitType:
    return _REGISTRY[unit_id]


def all_units() -> list[UnitType]:
    return list(_REGISTRY.values())
