'''
Python classes for the Borsdata API using local file caching and lazy loading.

You would probably not use the sub-modules directly. Instead you would ask a class for instances by a key, like this:

```python
from borsdata import Instrument
i1 = Instrument.get_by_ticker('FNOX')
i2 = Instrument.get_by_isin('SE0015192067')
```

Given a key, you will always get the same instance back.

TODO: also make sure that different `get_by_xxx` methods return the same instance when applicable
'''

from .branch import Branch
from .instrument import Instrument
from .sector import Sector
