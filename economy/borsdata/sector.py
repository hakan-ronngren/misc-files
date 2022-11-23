from . import borsdata as api


class Sector:
    def __init__(self, item):
        self.name = item['name']

    @classmethod
    def get_by_id(cls, oid: int) -> 'Sector':
        return _by_id.get(oid)


def _get_dicts():
    global _dicts
    if _dicts is None:
        _dicts = api.get_data('/v1/sectors', 86400)['sectors']
    return _dicts


_dicts = None
_by_id = api.LazyInstantiator(_get_dicts(), Sector, 'id')
