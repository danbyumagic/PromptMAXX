# Solira tiny-LLM pipeline. Run `make all` to reproduce end to end.
PY ?= python3
SRC = src
DOCS ?= 50000
STEPS ?= 3000

.PHONY: all corpus tokenizer train sample export sample-numpy chat clean

all: corpus tokenizer train export sample ## full pipeline

corpus: ## generate the Solira training corpus
	$(PY) $(SRC)/generate_corpus.py --docs $(DOCS)

tokenizer: ## train the BPE tokenizer
	$(PY) $(SRC)/tokenizer.py --vocab-size 512

train: ## train the ~1.1M param model
	$(PY) $(SRC)/train.py --max-steps $(STEPS)

sample: ## sample text from the trained model (PyTorch)
	$(PY) $(SRC)/generate.py --num-samples 6

chat: ## interactive generation REPL
	$(PY) $(SRC)/generate.py --chat

export: ## export weights to a numpy .npz (torch-free inference)
	$(PY) $(SRC)/export_numpy.py

sample-numpy: ## sample using the numpy-only backend
	$(PY) $(SRC)/generate_numpy.py --num-samples 6

clean: ## remove generated data/checkpoints
	rm -f data/corpus.txt data/val.txt data/tokenizer.json data/*.bin \
	      data/model.pt data/model_weights.npz data/model_config.json data/train.log
