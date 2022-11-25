from typing import List
from functools import cached_property

from . import borsdata as api
from .branch import Branch
from .sector import Sector
from .kpi import KPI


class InstrumentDay:
    def __init__(self, item) -> 'InstrumentDay':
        self.date = item['d']
        self.highest_price = item['h']
        self.lowest_price = item['l']
        self.closing_price = item['c']
        self.opening_price = item['o']
        self.volume = item['v']


class InstrumentDividend:
    def __init__(self, item) -> 'InstrumentDividend':
        self.year = item['y']
        self.value = item['v']
        # Unclear what p is. For 'AAK', 'ABB B', 'INVE B', and 'SSAB B'
        # the p value for 2022 (the latest) is 3, for older it is 5.
        self.p = item['p']


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
        data = api.get_data(f'/v1/instruments/{self.oid}/stockprices')
        return list(InstrumentDay(item) for item in data['stockPricesList'])

    @cached_property
    def dividends(self) -> List[InstrumentDividend]:
        data = api.get_data(f'/v1/instruments/{self.oid}/kpis/{KPI.DIVIDEND_ID}/year/mean/history', maxCount=20)
        # TODO: honour the introduction date
        return list(InstrumentDividend(item) for item in data['values'])

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
    return api.get_data('/v1/instruments')['instruments']


_instantiator = api.LazyInstantiator(_get_dicts, Instrument, ['insId', 'isin', 'ticker'])
