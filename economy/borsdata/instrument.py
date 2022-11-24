from typing import List
from functools import cached_property

from . import borsdata as api
from .branch import Branch
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
        self.oid = item['insId']
        self.name = item['name']
        self.ticker = item['ticker']
        self._sector_id = item['sectorId']
        self._branch_id = item['branchId']

    @cached_property
    def branch(self) -> str:
        return Branch.get_by_id(self._branch_id)

    @cached_property
    def sector(self) -> str:
        return Sector.get_by_id(self._sector_id)

    @cached_property
    def days(self) -> List[InstrumentDay]:
        data = api.get_data(f'/v1/instruments/{self.oid}/stockprices', 86400)
        return list(InstrumentDay(item) for item in data['stockPricesList'])

    @classmethod
    def get_by_id(cls, oid: int) -> 'Instrument':
        return _instantiator.get('insId', oid)

    @classmethod
    def get_by_isin(cls, isin: str) -> 'Instrument':
        return _instantiator.get('isin', isin)

    @classmethod
    def get_by_ticker(cls, ticker: str) -> 'Instrument':
        return _instantiator.get('ticker', ticker)


def _get_dicts():
    return api.get_data('/v1/instruments', 86400)['instruments']


_instantiator = api.LazyInstantiator(_get_dicts, Instrument, ['insId', 'isin', 'ticker'])
