from typing import List

from . import api
from . import sector
from . import index


class InstrumentDay:
    def __init__(self, item) -> 'InstrumentDay':
        self.date = item['d']
        self.highest_price = item['h']
        self.lowest_price = item['l']
        self.closing_price = item['c']
        self.opening_price = item['o']
        self.volume = item['v']


class Instrument:
    def __init__(self, item):
        print(f'building Instrument from {item}')
        self.oid = item['insId']
        self.name = item['name']
        self.ticker = item['ticker']
        self._sector_id = item['sectorId']

    @classmethod
    def all_from_api(_):
        data = api.get_data('/v1/instruments', 86400)
        return data['instruments']

    @property
    def sector(self) -> str:
        if not hasattr(self, '_sector'):
            self._sector = sector.get_by_oid(self._sector_id)
        return self._sector

    @property
    def days(self) -> List[InstrumentDay]:
        if not hasattr(self, '_days'):
            data = api.get_data(f'/v1/instruments/{self.oid}/stockprices', 86400)
            self._days = list(InstrumentDay(item) for item in data['stockPricesList'])
        return self._days


_by_id = index.Index(Instrument, 'insId')
_by_ticker = index.Index(Instrument, 'ticker')

def get_by_oid(oid: int) -> Instrument:
    return _by_id.get(oid)

def get_by_ticker(ticker: str) -> Instrument:
    return _by_ticker.get(ticker)
