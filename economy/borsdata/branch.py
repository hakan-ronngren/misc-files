from . import borsdata as api
from .sector import Sector


class Branch:
    def __init__(self, item):
        self.name = item['name']
        self._sector_id = item['sectorId']

    @classmethod
    def get_by_id(cls, oid: int) -> 'Branch':
        return _instantiator.get('id', oid)

    @property
    def sector(self) -> str:
        if not hasattr(self, '_sector'):
            self._sector = Sector.get_by_id(self._sector_id)
        return self._sector


def _get_dicts():
    global _dicts
    if _dicts is None:
        _dicts = api.get_data('/v1/branches', 86400)['branches']
    return _dicts


_dicts = None
_instantiator = api.LazyInstantiator(_get_dicts(), Branch, ['id'])
