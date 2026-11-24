"""Small, file-I/O-free helpers for modern Tiled TSX Wang sets."""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Iterable, Iterator, Mapping
from copy import deepcopy
from dataclasses import dataclass
from itertools import product
from xml.etree.ElementTree import Element

Signature = tuple[int, ...]

# Tiled stores these clockwise, starting at the upper edge.
SLOTS = ("top", "top_right", "right", "bottom_right", "bottom", "bottom_left", "left", "top_left")
_INDICES = {"edge": (0, 2, 4, 6), "corner": (1, 3, 5, 7), "mixed": tuple(range(8))}
_EMPTY = (0,) * len(SLOTS)


def _indices(kind: str) -> tuple[int, ...]:
    if kind not in _INDICES:
        raise ValueError(f"unknown Wang set type {kind!r}; expected corner, edge, or mixed")
    return _INDICES[kind]


def _value(value: int, field: str, maximum: int | None = None) -> int:
    if type(value) is not int or value < 0 or (maximum is not None and value > maximum):
        limit = f"0..{maximum}" if maximum is not None else "a non-negative integer"
        raise ValueError(f"{field} must be {limit}, got {value!r}")
    return value


def _xml_int(text: str | None, field: str) -> int:
    try:
        number = int(text) if text is not None else -1
    except ValueError as exc:
        raise ValueError(f"{field} must be a non-negative integer, got {text!r}") from exc
    return _value(number, field)


def slot_names(kind: str) -> tuple[str, ...]:
    """Names of the active slots, in Tiled order."""
    return tuple(SLOTS[index] for index in _indices(kind))


def _signature(kind: str, values: Iterable[int]) -> Signature:
    indices = _indices(kind)
    result = tuple(values)
    if len(result) != len(SLOTS):
        raise ValueError(f"Wang signature must have eight slots, got {len(result)}")
    for index, value in enumerate(result):
        _value(value, SLOTS[index], 255)
        if index not in indices and value != 0:
            raise ValueError(f"{SLOTS[index]} is inactive for a {kind} Wang set and must be 0")
    return result


def pack_slots(kind: str, slots: Mapping[str, int]) -> Signature:
    """Pack all named active slots into an eight-slot signature. Use 0 explicitly."""
    expected = set(slot_names(kind))
    missing, extra = expected - slots.keys(), slots.keys() - expected
    if missing or extra:
        raise ValueError(f"unexpected slots {sorted(extra, key=str)}; missing slots {sorted(missing)}")
    return _signature(kind, (slots.get(name, 0) for name in SLOTS))


def unpack_slots(kind: str, signature: Iterable[int]) -> dict[str, int]:
    """Return the named active slots; inactive slots are validated and omitted."""
    result = _signature(kind, signature)
    return {SLOTS[index]: result[index] for index in _indices(kind)}


def parse_wangid(kind: str, text: str) -> Signature:
    """Parse the comma-separated XML attribute, validating its slot layout."""
    return _signature(kind, (_xml_int(piece.strip(), "wangid component") for piece in text.split(",")))


def format_wangid(kind: str, signature: Iterable[int]) -> str:
    """Serialize a signature without shifting, mirroring, or inferring values."""
    return ",".join(map(str, _signature(kind, signature)))


def full_signatures(kind: str, values: Iterable[int]) -> Iterator[Signature]:
    """Enumerate an explicitly requested Cartesian product, excluding all-zero.

    Include 0 in values only if unset/blank contacts are part of the contract.
    This is for full coverage, not the default for pair-limited terrain sets.
    """
    indices = _indices(kind)
    choices = tuple(sorted({_value(value, "terrain index", 255) for value in values}))
    if not choices:
        raise ValueError("at least one terrain index is required")
    for combination in product(choices, repeat=len(indices)):
        if not any(combination):
            continue
        result = list(_EMPTY)
        for index, value in zip(indices, combination):
            result[index] = value
        yield tuple(result)


@dataclass(frozen=True)
class Coverage:
    missing: tuple[Signature, ...]
    extra: tuple[Signature, ...]
    # (signature, sorted local tile IDs). Variants are not an error.
    variants: tuple[tuple[Signature, tuple[int, ...]], ...]


def compare_coverage(
    kind: str, expected: Iterable[Signature], actual: Mapping[int, Signature]
) -> Coverage:
    """Compare only against the supplied requirements; extra values are informational."""
    _indices(kind)
    required = {_assigned(kind, signature) for signature in expected}
    groups: dict[Signature, list[int]] = defaultdict(list)
    for tile_id, signature in actual.items():
        groups[_assigned(kind, signature)].append(_value(tile_id, "tile id"))
    return Coverage(
        missing=tuple(sorted(required - groups.keys())),
        extra=tuple(sorted(groups.keys() - required)),
        variants=tuple((signature, tuple(sorted(ids))) for signature, ids in sorted(groups.items()) if len(ids) > 1),
    )


def _assigned(kind: str, values: Iterable[int], colors: int = 255) -> Signature:
    result = _signature(kind, values)
    if not any(result):
        raise ValueError("an all-zero signature is not a tile assignment; use a blank map cell")
    if max(result) > colors:
        raise ValueError(f"signature uses terrain index {max(result)}, but the set has {colors} colors")
    return result


def _set_info(wangset: Element) -> tuple[str, int]:
    if wangset.tag != "wangset":
        raise ValueError("expected a <wangset> element")
    kind = wangset.get("type", "")
    _indices(kind)
    colors = _value(len(wangset.findall("wangcolor")), "Wang color count", 255)
    return kind, colors


def read_assignments(wangset: Element) -> dict[int, Signature]:
    """Read local tile IDs and validated signatures from one modern Wang set."""
    kind, colors = _set_info(wangset)
    result = {}
    for child in wangset.findall("wangtile"):
        tile_id = _xml_int(child.get("tileid"), "wangtile tileid")
        if tile_id in result:
            raise ValueError(f"tile id {tile_id} is assigned more than once in this Wang set")
        raw = child.get("wangid")
        if raw is None:
            raise ValueError(f"tile id {tile_id} has no wangid")
        result[tile_id] = _assigned(kind, parse_wangid(kind, raw), colors)
    return result


def _find_set(tileset: Element, set_name: str) -> Element:
    if tileset.tag != "tileset" or "source" in tileset.attrib:
        raise ValueError("expected the loaded <tileset> definition, not an external source reference")
    matches = [node for node in tileset.findall("wangsets/wangset") if node.get("name") == set_name]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one Wang set named {set_name!r}, found {len(matches)}")
    return matches[0]


def patch_assignments(
    tileset: Element, set_name: str, updates: Mapping[int, Signature | None]
) -> Element:
    """Return a copy with only the named set's explicitly listed local tile IDs edited.

    A signature adds or replaces that tile's wangid. None explicitly removes an
    existing assignment. No document is saved and the input tree is not edited.
    """
    target = _find_set(tileset, set_name)
    kind, colors = _set_info(target)
    existing = read_assignments(target)
    if tileset.find("image") is not None:
        valid_ids = range(_xml_int(tileset.get("tilecount"), "atlas tilecount"))
    else:
        # Image collections can have holes; tilecount is not a bound on local IDs.
        valid_ids = {_xml_int(node.get("id"), "collection tile id") for node in tileset.findall("tile")}

    checked: dict[int, Signature | None] = {}
    for tile_id, signature in updates.items():
        _value(tile_id, "tile id")
        if signature is None:
            if tile_id not in existing:
                raise ValueError(f"cannot remove unassigned tile id {tile_id}")
            checked[tile_id] = None
        else:
            if tile_id not in valid_ids:
                raise ValueError(f"tile id {tile_id} does not exist in this tileset")
            checked[tile_id] = _assigned(kind, signature, colors)

    result = deepcopy(tileset)
    output = _find_set(result, set_name)
    nodes = {_xml_int(node.get("tileid"), "wangtile tileid"): node for node in output.findall("wangtile")}
    for tile_id, signature in sorted(checked.items()):
        if signature is None:
            output.remove(nodes[tile_id])
            continue
        node = nodes.get(tile_id)
        if node is None:
            node = Element("wangtile", tileid=str(tile_id))
            output.append(node)
        node.set("wangid", format_wangid(kind, signature))
    return result
