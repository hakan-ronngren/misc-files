from typing import List

from . import api
from . import sector


class InstrumentDay:
    def __init__(self, item) -> 'InstrumentDay':
        self.date = item['d']
        self.closing_price = item['c']
        self.volume = item['v']


class Instrument:
    memory_cache = dict()
    api_path = '/v1/instruments'
    max_disk_cache_age_seconds = 86400
    response_key = 'instruments'
    id_key = 'insId'

    def __init__(self, item):
        print(f'building Instrument from {item}')
        self.id = item['insId']
        self.name = item['name']
        self.ticker = item['ticker']
        self._sector_id = item['sectorId']

    @property
    def sector(self) -> str:
        if not hasattr(self, '_sector'):
            self._sector = sector.get_by_id(self._sector_id)
        return self._sector

    @property
    def days(self) -> List[InstrumentDay]:
        if not hasattr(self, '_days'):
            data = api.get_data(f'/v1/instruments/{self.id}/stockprices', 86400)
            self._days = list(InstrumentDay(item) for item in data['stockPricesList'])
        return self._days


def get_by_id(id) -> Instrument:
    return api.get_by_id(id, Instrument)

