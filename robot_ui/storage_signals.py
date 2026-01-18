import json
from pathlib import Path
from typing import Dict

def ensure_signal_names_file(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return
    # Default names: Robot1..4, inputs/outputs 1..64
    data: Dict[str, Dict[str, Dict[str, str]]] = {}
    for rid in range(1, 5):
        rkey = f"robot_{rid}"
        data[rkey] = {"inputs": {}, "outputs": {}}
        for i in range(1, 65):
            data[rkey]["inputs"][str(i)] = f"IN{i:02d}"
            data[rkey]["outputs"][str(i)] = f"OUT{i:02d}"
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")

def load_signal_names(path: Path) -> Dict:
    return json.loads(path.read_text(encoding="utf-8"))

def get_name(signal_names: Dict, robot_id: int, kind: str, num: int) -> str:
    # kind: "inputs" or "outputs"
    rkey = f"robot_{robot_id}"
    return signal_names.get(rkey, {}).get(kind, {}).get(str(num), f"{kind.upper()}_{num}")
