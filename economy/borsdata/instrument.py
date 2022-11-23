from typing import List

from . import borsdata as api
from .sector import Sector


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

    @property
    def sector(self) -> str:
        if not hasattr(self, '_sector'):
            self._sector = Sector.get_by_id(self._sector_id)
        return self._sector

    @property
    def days(self) -> List[InstrumentDay]:
        if not hasattr(self, '_days'):
            data = api.get_data(f'/v1/instruments/{self.oid}/stockprices', 86400)
            self._days = list(InstrumentDay(item) for item in data['stockPricesList'])
        return self._days

    @classmethod
    def get_by_id(cls, oid: int) -> 'Instrument':
        return _by_id.get(oid)

    @classmethod
    def get_by_isin(cls, oid: int) -> 'Instrument':
        return _by_isin.get(oid)

    @classmethod
    def get_by_ticker(cls, ticker: str) -> 'Instrument':
        return _by_ticker.get(ticker)


def _get_dicts():
    global _dicts
    if _dicts is None:
        _dicts = api.get_data('/v1/instruments', 86400)['instruments']
    return _dicts


_dicts = None
_by_id = api.LazyInstantiator(_get_dicts(), Instrument, 'insId')
_by_isin = api.LazyInstantiator(_get_dicts(), Instrument, 'isin')
_by_ticker = api.LazyInstantiator(_get_dicts(), Instrument, 'ticker')
