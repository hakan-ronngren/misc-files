#!/usr/bin/env python3

from borsdata import instrument

instr = instrument.get_by_oid(999)
print(f'instrument name: {instr.name}')
print(f'ticker: {instr.ticker}')
print(f'sector name: {instr.sector.name}')
print(f'price on {instr.days[3].date}: {instr.days[3].closing_price}')

instr = instrument.get_by_ticker('FNOX')
print(f'instrument name: {instr.name}')
