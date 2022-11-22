from . import api
from . import index


class Sector:
    def __init__(self, item):
        self.name = item['name']

    @classmethod
    def all_from_api(cls):
        data = api.get_data('/v1/sectors', 86400)
        return data['sectors']


_by_id = index.Index(Sector, 'id')

def get_by_oid(oid: int) -> Sector:
    return _by_id.get(oid)
