.PHONY: test unittest pep8 pip

test: unittest pep8

unittest: venv
	. venv/bin/activate \
	&& python -m unittest discover -v tests

pep8: venv
	. venv/bin/activate \
	&& pycodestyle --ignore=E501,W503,W504 borsdata tests

venv:
	python3 -m venv venv

pip: venv
	. venv/bin/activate \
	&& pip install --upgrade pip \
	&& pip install -r requirements.txt
