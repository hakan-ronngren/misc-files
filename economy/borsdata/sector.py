from . import borsdata as api


class Sector:
    def __init__(self, item):
        self.name = item['name']


_dicts = api.get_data('/v1/sectors', 86400)['sectors']
_by_id = api.LazyInstantiator(_dicts, Sector, 'id')


def get_by_oid(oid: int) -> Sector:
    return _by_id.get(oid)
