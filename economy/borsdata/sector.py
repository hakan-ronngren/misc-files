from . import borsdata as api


class Sector:
    def __init__(self, item):
        self.name = item['name']

    @classmethod
    def get_by_id(cls, oid: int) -> 'Sector':
        return _instantiator.get('id', oid)


def _get_dicts():
    return api.get_data('/v1/sectors')['sectors']


_instantiator = api.LazyInstantiator(_get_dicts, Sector, ['id'])
