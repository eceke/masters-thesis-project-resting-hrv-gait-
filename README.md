# Resting-State Cardiac Activity, Gait, and Memory

MATLAB code for processing ECG and movement recordings and examining associations between resting-state cardiac indicators and subsequent gait performance. The repository also includes exploratory memory analyses.

## Repository structure

| Folder | Purpose |
| --- | --- |
| `code/Epoching of Experiment Data` | Aligns recordings, identifies markers, and extracts experimental segments. |
| `code/Preprocess and Data Extraction of Epoched files` | Cleans segmented data and prepares analysis tables. |
| `code/Thesis Main Analysis` | Runs the HRV–gait models, sensitivity analyses, and diagnostics. |
| `code/Memory HRV-Gait Analysis` | Runs exploratory recall accuracy, precision, and valence analyses. |

## Workflow

1. Process each participant's raw recordings with `run_align.m` and `run_epoch.m` in `code/Epoching of Experiment Data/runs/`.
2. Run `run_full_pipeline.m` in `code/Preprocess and Data Extraction of Epoched files/runs/` to create the analysis tables.
3. Run `run_analysis.m` in `code/Thesis Main Analysis/` for the HRV–gait analysis. By default, it reads `data/LMM_HRV_GAIT_long.csv` within that folder. Its `DataFile` and `OutputDir` options can override these locations.
4. Run `run_memory_analysis_accuracy.m` or `run_memory_analysis_valence.m` in `code/Memory HRV-Gait Analysis/src/` for exploratory memory analyses. These scripts prompt for the memory input files and analysis settings.

Run each entry point from MATLAB with its containing folder selected as the Current Folder. The main analysis requires the Statistics and Machine Learning Toolbox. Source data must be supplied separately before running the pipelines.

## Data and generated files

Participant-level recordings, recall spreadsheets, the Kinesis workbook, analysis input tables, and generated outputs are not included in this repository. The `.gitignore` excludes the corresponding data and output folders. The code documents the expected input filenames and directory locations.
