import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _bldg_eel import *


class Config(Eel):
    name = "ElectricEelTrap"
    stage = 1
