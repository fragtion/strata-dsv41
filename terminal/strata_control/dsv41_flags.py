"""What a DeepSeek engine program accepts, asked of the program itself.  No network: the server imports this."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

_SEEN: dict = {}


def _env(exe: Path) -> dict:
    """The environment with the engine's own folder first on the library path (the GPU runtime libraries sit beside the program)."""
    env = dict(os.environ)
    var = "PATH" if os.name == "nt" else "LD_LIBRARY_PATH"
    env[var] = os.pathsep.join([str(exe.parent)] + ([env[var]] if env.get(var) else []))
    return env


def takes_parallel(exe, timeout: float = 15.0) -> bool | None:
    """Does this DeepSeek engine take `--parallel N` (several conversations at once)?  Asked of the engine itself: its usage text (`--help`,
    which needs no card and no model) names the flag from the version that has it.  True / False; None when it cannot be told (no such file,
    it would not start, no usage text came back) - then nothing is decided and the caller goes on as before.  Remembered per file and time."""
    try:
        path = Path(str(exe))
        st = path.stat()
        key = (str(path), st.st_mtime_ns, st.st_size)
    except (OSError, ValueError, TypeError):
        return None
    if key in _SEEN:
        return _SEEN[key]
    answer: bool | None = None
    try:
        done = subprocess.run([str(path), "--help"], capture_output=True, text=True, errors="replace", timeout=timeout, cwd=str(path.parent),
                              env=_env(path), stdin=subprocess.DEVNULL)
        text = (done.stdout or "") + (done.stderr or "")
        if "--pack" in text and "--serve" in text:        # its own usage text (every version prints these two)
            answer = "--parallel" in text
    except (OSError, subprocess.SubprocessError):
        answer = None
    _SEEN[key] = answer
    return answer
