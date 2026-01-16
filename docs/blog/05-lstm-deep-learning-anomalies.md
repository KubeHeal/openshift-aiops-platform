# Deep Learning for Cluster Anomalies: LSTM Networks

*Part 5 of the OpenShift AI Ops Learning Series*

---

## Introduction

Deep learning brings powerful sequence modeling capabilities to anomaly detection. LSTM (Long Short-Term Memory) networks excel at learning temporal patterns in time series data, making them ideal for detecting gradual degradation, memory leaks, and complex multi-metric anomalies.

This guide walks you through building an LSTM autoencoder that learns normal cluster behavior and flags deviations as anomalies using reconstruction error.

---

## What You'll Learn

- Introduction to LSTM neural networks
- Building autoencoders for anomaly detection
- Sequence-based anomaly detection
- Training on GPU with OpenShift AI
- When to use deep learning vs. traditional ML

---

## Prerequisites

Before starting, ensure you have:

- [ ] Completed [Blog 3: Isolation Forest](03-isolation-forest-anomaly-detection.md)
- [ ] Completed [Blog 4: Time Series Detection](04-time-series-anomaly-detection.md)
- [ ] GPU-enabled node available (recommended)
- [ ] PyTorch installed in workbench
- [ ] Time series data collected

---

## Understanding LSTM Networks

### What is LSTM?

LSTM (Long Short-Term Memory) is a type of recurrent neural network (RNN) designed to learn long-term dependencies in sequences.

**Key Features:**
- **Memory cells**: Remember information for long periods
- **Gates**: Control what to remember/forget (input, forget, output gates)
- **Sequential processing**: Processes data point by point, maintaining context

### Why LSTM for Anomalies?

- ✅ **Sequence learning**: Captures patterns across time steps
- ✅ **Context awareness**: Understands relationships between past and present
- ✅ **Multi-metric**: Can learn complex interactions between CPU, memory, network
- ✅ **Gradual changes**: Detects slow memory leaks that threshold methods miss

### Autoencoder Architecture

An autoencoder learns to compress and reconstruct normal data:

```
Input → Encoder → Latent Space → Decoder → Reconstruction
```

**Anomaly Detection Principle:**
- Train on normal data only
- Anomalies have high reconstruction error (can't be reconstructed well)
- Threshold reconstruction error to flag anomalies

---

## Step 1: Prepare Sequence Data

### Open the LSTM Notebook

1. Navigate to `notebooks/02-anomaly-detection/`
2. Open `03-lstm-based-prediction.ipynb`

### Create Sequences

LSTMs require sequences (windows of time steps):

```python
import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler

def create_sequences(data, sequence_length=60):
    """
    Create sequences from time series data.

    Args:
        data: DataFrame with metrics
        sequence_length: Number of time steps per sequence

    Returns:
        X: Sequences of shape (samples, sequence_length, features)
        y: Next value (for supervised) or reconstruction target
    """
    sequences = []
    targets = []

    for i in range(len(data) - sequence_length):
        seq = data.iloc[i:i+sequence_length].values
        target = data.iloc[i+sequence_length].values
        sequences.append(seq)
        targets.append(target)

    return np.array(sequences), np.array(targets)

# Load metrics
metrics = pd.read_parquet('/opt/app-root/src/data/prometheus/cpu_metrics.parquet')

# Normalize
scaler = StandardScaler()
metrics_scaled = scaler.fit_transform(metrics[['cpu_usage', 'memory_usage']])

# Create sequences (60 time steps = 1 hour if 1-minute intervals)
X, y = create_sequences(pd.DataFrame(metrics_scaled), sequence_length=60)

print(f"📊 Sequences created: {X.shape}")
print(f"   Samples: {X.shape[0]}")
print(f"   Sequence length: {X.shape[1]}")
print(f"   Features: {X.shape[2]}")
```

---

## Step 2: Build LSTM Autoencoder

### Define Model Architecture

```python
import torch
import torch.nn as nn

class LSTMAutoencoder(nn.Module):
    """
    LSTM Autoencoder for anomaly detection.

    Architecture:
    - Encoder: LSTM layers compress input
    - Decoder: LSTM layers reconstruct output
    """
    def __init__(self, input_dim, hidden_dim=64, num_layers=2):
        super(LSTMAutoencoder, self).__init__()

        # Encoder
        self.encoder = nn.LSTM(
            input_dim,
            hidden_dim,
            num_layers,
            batch_first=True
        )

        # Latent representation
        self.latent_dim = hidden_dim

        # Decoder
        self.decoder = nn.LSTM(
            hidden_dim,
            hidden_dim,
            num_layers,
            batch_first=True
        )

        # Output layer
        self.output_layer = nn.Linear(hidden_dim, input_dim)

    def forward(self, x):
        # Encode
        encoded, (hidden, cell) = self.encoder(x)

        # Use last hidden state as latent representation
        latent = hidden[-1]  # Last layer's hidden state

        # Repeat latent for decoder input
        decoder_input = latent.unsqueeze(1).repeat(1, x.size(1), 1)

        # Decode
        decoded, _ = self.decoder(decoder_input)

        # Output
        output = self.output_layer(decoded)

        return output, latent
```

### Initialize Model

```python
# Check for GPU
device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
print(f"🖥️ Using device: {device}")

# Create model
model = LSTMAutoencoder(
    input_dim=2,  # CPU and memory
    hidden_dim=64,
    num_layers=2
).to(device)

print(f"✅ Model created: {sum(p.numel() for p in model.parameters())} parameters")
```

---

## Step 3: Train the Model

### Prepare Data Loader

```python
from torch.utils.data import DataLoader, TensorDataset

# Convert to tensors
X_tensor = torch.FloatTensor(X).to(device)
y_tensor = torch.FloatTensor(y).to(device)

# Create dataset (for autoencoder, target = input)
dataset = TensorDataset(X_tensor, X_tensor)  # Reconstruct input

# Split train/test (use only normal data for training)
train_size = int(len(dataset) * 0.8)
train_dataset = torch.utils.data.Subset(dataset, range(train_size))
test_dataset = torch.utils.data.Subset(dataset, range(train_size, len(dataset)))

# Create data loaders
train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True)
test_loader = DataLoader(test_dataset, batch_size=32, shuffle=False)

print(f"📊 Training samples: {len(train_dataset)}")
print(f"📊 Test samples: {len(test_dataset)}")
```

### Training Loop

```python
import torch.optim as optim

# Loss function (Mean Squared Error for reconstruction)
criterion = nn.MSELoss()
optimizer = optim.Adam(model.parameters(), lr=0.001)

# Training
num_epochs = 50
model.train()

for epoch in range(num_epochs):
    total_loss = 0

    for batch_x, batch_y in train_loader:
        optimizer.zero_grad()

        # Forward pass
        reconstructed, latent = model(batch_x)

        # Calculate reconstruction error
        loss = criterion(reconstructed, batch_y)

        # Backward pass
        loss.backward()
        optimizer.step()

        total_loss += loss.item()

    avg_loss = total_loss / len(train_loader)

    if (epoch + 1) % 10 == 0:
        print(f"Epoch [{epoch+1}/{num_epochs}], Loss: {avg_loss:.4f}")

print("✅ Training complete!")
```

---

## Step 4: Detect Anomalies

### Calculate Reconstruction Error

```python
model.eval()
reconstruction_errors = []

with torch.no_grad():
    for batch_x, batch_y in test_loader:
        reconstructed, _ = model(batch_x)

        # Calculate MSE for each sample
        mse = torch.mean((reconstructed - batch_y) ** 2, dim=(1, 2))
        reconstruction_errors.extend(mse.cpu().numpy())

reconstruction_errors = np.array(reconstruction_errors)

print(f"📊 Reconstruction errors calculated")
print(f"   Mean: {reconstruction_errors.mean():.4f}")
print(f"   Std: {reconstruction_errors.std():.4f}")
print(f"   Max: {reconstruction_errors.max():.4f}")
```

### Set Anomaly Threshold

```python
# Use statistical threshold (e.g., mean + 2*std)
threshold = reconstruction_errors.mean() + 2 * reconstruction_errors.std()

# Or use percentile (e.g., top 5%)
threshold_percentile = np.percentile(reconstruction_errors, 95)

print(f"🔍 Anomaly threshold (mean+2σ): {threshold:.4f}")
print(f"🔍 Anomaly threshold (95th percentile): {threshold_percentile:.4f}")

# Detect anomalies
anomalies = reconstruction_errors > threshold

print(f"⚠️ Detected {anomalies.sum()} anomalies ({anomalies.sum()/len(anomalies)*100:.1f}%)")
```

### Visualize Anomalies

```python
import matplotlib.pyplot as plt

# Plot reconstruction errors
plt.figure(figsize=(14, 6))
plt.plot(reconstruction_errors, label='Reconstruction Error', alpha=0.7)
plt.axhline(y=threshold, color='red', linestyle='--', label='Threshold')
plt.scatter(np.where(anomalies)[0],
           reconstruction_errors[anomalies],
           color='red', s=50, marker='x', label='Anomalies', zorder=5)
plt.xlabel('Sample')
plt.ylabel('Reconstruction Error')
plt.title('LSTM Anomaly Detection')
plt.legend()
plt.grid(True)
plt.show()
```

---

## Step 5: Evaluate Performance

If you have labeled anomaly data:

```python
from sklearn.metrics import precision_score, recall_score, f1_score

# Assuming you have ground truth
y_true = test_labels  # Boolean array: True = anomaly

# Calculate metrics
precision = precision_score(y_true, anomalies)
recall = recall_score(y_true, anomalies)
f1 = f1_score(y_true, anomalies)

print("📊 LSTM Performance:")
print(f"   Precision: {precision:.3f}")
print(f"   Recall: {recall:.3f}")
print(f"   F1-Score: {f1:.3f}")
```

---

## Step 6: Save Model for Production

```python
# Save model
model_path = '/opt/app-root/src/models/lstm-predictor/lstm_autoencoder.pth'
torch.save({
    'model_state_dict': model.state_dict(),
    'scaler': scaler,
    'threshold': threshold,
    'input_dim': 2,
    'hidden_dim': 64,
    'num_layers': 2
}, model_path)

print(f"✅ Model saved: {model_path}")
```

---

## What Just Happened?

You've built a deep learning anomaly detector:

### 1. LSTM Architecture

- **Encoder**: Compresses input sequences into latent representation
- **Decoder**: Reconstructs sequences from latent representation
- **Memory cells**: Remember long-term patterns in sequences

### 2. Training Strategy

- **Unsupervised**: Trained only on normal data
- **Reconstruction**: Learns to reconstruct normal patterns
- **GPU acceleration**: Fast training on NVIDIA GPUs

### 3. Anomaly Detection

- **Reconstruction error**: Anomalies can't be reconstructed well
- **Statistical threshold**: Mean + 2 standard deviations
- **Sequence-aware**: Detects anomalies in temporal context

### 4. Advantages Over Traditional ML

- **Complex patterns**: Learns non-linear relationships
- **Multi-metric**: Handles interactions between CPU, memory, network
- **Gradual changes**: Detects slow memory leaks
- **Context**: Understands sequences, not just individual points

---

## When to Use LSTM vs. Traditional ML

### Use LSTM When:
- ✅ Complex temporal patterns (gradual degradation)
- ✅ Multi-metric interactions (CPU + memory + network)
- ✅ Long sequences (hours to days of data)
- ✅ GPU available for training
- ✅ Large dataset (>10k samples)

### Use Traditional ML (Isolation Forest) When:
- ✅ Simple patterns (threshold-based)
- ✅ Fast inference required (<10ms)
- ✅ Limited data (<1k samples)
- ✅ Interpretability important
- ✅ No GPU available

### Use Both:
- **Ensemble**: Combine LSTM + Isolation Forest (see [Blog 6](06-ensemble-anomaly-methods.md))
- **Different use cases**: LSTM for sequences, Isolation Forest for point anomalies

---

## Tuning Tips

### Adjust Model Capacity

```python
# Larger model (more capacity)
model = LSTMAutoencoder(input_dim=2, hidden_dim=128, num_layers=3)

# Smaller model (faster, less capacity)
model = LSTMAutoencoder(input_dim=2, hidden_dim=32, num_layers=1)
```

### Adjust Sequence Length

```python
# Longer sequences (more context)
X, y = create_sequences(data, sequence_length=120)  # 2 hours

# Shorter sequences (faster training)
X, y = create_sequences(data, sequence_length=30)   # 30 minutes
```

### Adjust Threshold

```python
# More sensitive (detect more anomalies)
threshold = reconstruction_errors.mean() + 1.5 * reconstruction_errors.std()

# Less sensitive (fewer false positives)
threshold = reconstruction_errors.mean() + 3.0 * reconstruction_errors.std()
```

---

## Next Steps

Explore advanced deep learning:

1. **Ensemble Methods**: [Blog 6: Ensemble Anomaly Methods](06-ensemble-anomaly-methods.md) to combine LSTM with other models
2. **Attention Mechanisms**: Add attention layers for better sequence understanding
3. **Transformer Models**: Use transformer architecture for even better performance

---

## Related Resources

- **Notebook**: `notebooks/02-anomaly-detection/03-lstm-based-prediction.ipynb`
- **ADRs**:
  - [ADR-006: NVIDIA GPU Operator](docs/adrs/006-nvidia-gpu-management.md)
  - [ADR-003: OpenShift AI for ML](docs/adrs/003-openshift-ai-ml-platform.md)
- **Research**:
  - [LSTM Paper](https://www.bioinf.jku.at/publications/older/2604.pdf) (Hochreiter & Schmidhuber, 1997)
  - [Time Series Anomaly Detection with LSTM](https://arxiv.org/abs/1607.00148) (Malhotra et al., 2016)
- **PyTorch Docs**: [LSTM](https://pytorch.org/docs/stable/generated/torch.nn.LSTM.html)

---

## Found an Issue?

If you encounter problems while following this guide:

1. **Open a GitHub Issue**: [Create Issue](https://github.com/tosin2013/openshift-aiops-platform/issues/new)
   - Use label: `blog-feedback`
   - Include: Blog name, step number, error message

2. **Contribute a Fix**: PRs welcome!
   - Fork the repo
   - Fix the issue in `docs/blog/05-lstm-deep-learning-anomalies.md`
   - Submit PR referencing the issue

Your feedback helps improve this guide for everyone!

---

*Part 5 of 15 in the OpenShift AI Ops Learning Series*
