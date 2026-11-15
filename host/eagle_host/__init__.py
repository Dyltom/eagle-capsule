"""Eagle Capsule host-side reference implementation (simulator + sync client).

See docs/SYNC-PROTOCOL.md for the wire and file formats implemented here.
"""

import logging

logging.getLogger(__name__).addHandler(logging.NullHandler())
