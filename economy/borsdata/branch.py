from functools import cached_property

from . import borsdata as api
from .sector import Sector


class Branch:
    def __init__(self, item):
        self.name = item['name']
        self._sector_id = item['sectorId']

    @cached_property
    def sector(self) -> str:
        return Sector.get_by_id(self._sector_id)

    @classmethod
    def get_by_id(cls, oid: int) -> 'Branch':
        return _instantiator.get('id', oid)


def _get_dicts():
    return api.get_data('/v1/branches', 86400)['branches']


_instantiator = api.LazyInstantiator(_get_dicts, Branch, ['id'])
