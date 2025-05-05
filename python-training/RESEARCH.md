peline with audio streaming and MFCC feature extraction), the next step is to collect your own wake word data. Record around 20–50 audio clips of the wake word using different voices, accents, and background environments. Then, apply augmentation techniques—like adding noise, pitch shifting, and speed variation—to simulate more diversity. This data can be combined with negative examples (e.g., unrelated words or silence) and used to fine-tune the model’s final layers for better accuracy and generalization.

Paragraph 3: Train and Deploy Lightweight Model Locally
With labeled audio data prepared, you can train a lightweight model (under 5MB quantized) using frameworks like PyTorch or TensorFlow. Once trained, export it to a portable format like ONNX or TFLite and run it locally using a minimal inference engine such as tract in Rust. At runtime, your system will stream microphone audio, apply VAD (optional), extract MFCC features, and feed them into the model every few hundred milliseconds. With appropriate smoothing and a confidence threshold, the system can robustly trigger on your wake word even in moderately noisy environments.

Pretrained Model + Training Datasets
📁 Google Speech Commands Dataset (v2, ~105k audio files)
https://www.tensorflow.org/datasets/catalog/speech_commands
(also mirrored at https://github.com/berndpfrommer/speech_commands)

Use as base for training or for generating negative examples (non-wake words).

📦 Example: Keyword Spotting with PyTorch
https://github.com/ARM-software/ML-KWS-for-MCU

Includes CNN/DS-CNN models

Optimized for low memory use (can quantize)

Model size: ~10MB uncompressed; ~2MB quantized

🧠 Fine-Tuning Tools & Wake Word Training Frameworks
🎤 Mycroft Precise — fully open-source wake word training + detection
https://github.com/MycroftAI/mycroft-precise

CLI tools to record, augment, train

Can export to TFLite for small inference footprint

Small models (~1–5 MB)

Good for prototyping custom phrases

🧪 Simple KWS training with PyTorch + torchaudio
https://github.com/jeysonmc/kws-pytorch

Great for getting started with fine-tuning

Includes MFCC + CNN-based training

Easily customizable for custom labels (like your wake word)

🎙️ Real-Time Audio Input
🎧 cpal Rust crate for audio input
https://github.com/RustAudio/cpal

Cross-platform, no heavy dependencies

Use to stream mic audio directly in Rust

🎤 sounddevice for Python (if prototyping STT or training tools)
https://python-sounddevice.readthedocs.io/

Easy interface to stream audio for VAD and STT

🧏 Speech-to-Text (STT) — Local, Small, Open Source
🗣️ Vosk API (Offline STT for Python, C++, Rust)
https://github.com/alphacep/vosk-api

Small STT model: https://alphacephei.com/vosk/models
Example: vosk-model-small-en-us-0.15 (~40MB)

Very easy to integrate after wake word trigger

Good accuracy for short phrases

🦀 Rust Vosk Bindings (Unofficial, works well)
https://github.com/silvia-odwyer/vosk-rs

Lets you run the same STT engine directly from Rust

🧰 Model Export & Inference (Local Runtime)
🧮 tract — run TFLite/ONNX in Rust (lightweight)
https://github.com/sonos/tract

Use to run exported wake word model locally

No need for Python or TensorFlow at runtime

🔁 ONNX Conversion for PyTorch
https://pytorch.org/tutorials/advanced/super_resolution_with_onnxruntime.html

Export wake word model to .onnx format

Load with tract or other Rust inference engines

