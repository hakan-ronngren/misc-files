#!/usr/bin/env python3

from borsdata import Instrument
from analysis import InstrumentStatistics

instr = Instrument.get_by_ticker('FNOX')
print(f'Instantiated the Instrument {instr.name}')
print(f'Its sector is {instr.sector.name}')

stats = InstrumentStatistics(instr)
print(stats.average())

instr = Instrument.get_by_isin('SE0015192067')
print(f'Instantiated the Instrument {instr.name}')
print(f'Its sector is {instr.sector.name}')
