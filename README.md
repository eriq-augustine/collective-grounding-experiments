Grounding experiments that work directly on the psl-examples repository.

## System Setup

Those who want to run the experiments will have to be sure that they can clear their postgres/system caches without manual intervention.
The easiest way is probably adding an exception in your sudoers file (assuming `wheel` is the sudoers group):
```
%wheel ALL=(ALL) NOPASSWD: /path/to/repo/psl-grounding-experiments/scripts/clear_cache.sh
```
