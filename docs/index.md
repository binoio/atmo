---
layout: default
title: Home
description: Atmo is a macOS app for discovering and controlling Apple TV devices.
---

<section class="hero">
  <div class="container">
    <h1>Atmo - Apple TV Remote</h1>
    <p>Atmo is a macOS app for discovering and controlling Apple TV devices.</p>
    <div class="hero-actions">
      <a href="https://github.com/mabino/atmo/releases/latest/download/Atmo-stapled.zip" class="btn btn-primary">
        <i class="fas fa-download"></i>
        Download Latest
      </a>
      <a href="https://github.com/mabino/atmo" class="btn btn-ghost" target="_blank">
        <i class="fab fa-github"></i>
        View on GitHub
      </a>
    </div>
  </div>
</section>

<section id="features" class="section">
  <div class="container">
    <h2>Features</h2>

    <div class="features-grid">
      <div class="feature-card">
        <div class="feature-icon">
          <i class="fas fa-search"></i>
        </div>
        <h4>Device Discovery</h4>
        <p>Automatically discover Apple TV devices on your local network.</p>
      </div>

      <div class="feature-card">
        <div class="feature-icon">
          <i class="fas fa-link"></i>
        </div>
        <h4>Seamless Pairing</h4>
        <p>Secure pairing with Apple TV devices.</p>
      </div>

      <div class="feature-card">
        <div class="feature-icon">
          <i class="fas fa-gamepad"></i>
        </div>
        <h4>Remote Control</h4>
        <p>Full remote control functionality with keyboard shortcuts.</p>
      </div>

      <div class="feature-card">
        <div class="feature-icon">
          <i class="fas fa-power-off"></i>
        </div>
        <h4>Power Management</h4>
        <p>Control power states of your Apple TV devices.</p>
      </div>

      <div class="feature-card">
        <div class="feature-icon">
          <i class="fas fa-code"></i>
        </div>
        <h4>Modern Architecture</h4>
        <p>Built with SwiftUI and Swift Concurrency.</p>
      </div>

      <div class="feature-card">
        <div class="feature-icon">
          <i class="fas fa-print"></i>
        </div>
        <h4>Device Reports</h4>
        <p>Generate reports of discovered devices with identifiers and connection details.</p>
      </div>
    </div>
  </div>
</section>

<section class="section screenshots">
  <div class="container">
    <h2>Screenshots</h2>

    <div class="screenshot-grid">
      <div class="screenshot">
        <img src="{{ '/assets/images/main-interface.png' | relative_url }}" alt="Main Interface" />
        <h4>Main Interface</h4>
        <p>Clean, modern interface showing discovered and paired Apple TV devices.</p>
      </div>

      <div class="screenshot">
        <img src="{{ '/assets/images/remote-control.png' | relative_url }}" alt="Remote Control" />
        <h4>Remote Control</h4>
        <p>Remote control interface with essential Apple TV functions.</p>
      </div>

      <div class="screenshot">
        <img src="{{ '/assets/images/remote-menu.png' | relative_url }}" alt="Menu Options" />
        <h4>Menu & Options</h4>
        <p>Access to essential functions via keyboard shortcuts.</p>
      </div>
    </div>
  </div>
</section>

<section id="architecture" class="section architecture">
  <div class="container">
    <h2>Architecture</h2>

    <div class="features-grid">
      <div class="feature-card">
        <h4>SwiftUI Frontend</h4>
        <ul>
          <li>ContentView - Main UI container</li>
          <li>BridgeViewModel - State management</li>
          <li>BridgeService - Python bridge communication</li>
        </ul>
      </div>

      <div class="feature-card">
        <h4>Python Bridge</h4>
        <ul>
          <li>CLI interface with JSON output</li>
          <li>Device discovery and pairing</li>
          <li>Remote control commands</li>
          <li>Power management</li>
        </ul>
      </div>

      <div class="feature-card">
        <h4>Communication</h4>
        <ul>
          <li>JSON-based messaging</li>
          <li>Asynchronous operations</li>
          <li>Error handling and logging</li>
          <li>Process lifecycle management</li>
        </ul>
      </div>
    </div>
  </div>
</section>

<section id="getting-started" class="section getting-started">
  <div class="container">
    <h2>Getting Started</h2>

    <div class="steps">
      <div class="step">
        <div class="step-number">1</div>
        <div>
          <h3>Install Python Dependencies</h3>
          <p>Set up the Python virtual environment and install required packages.</p>
        </div>
      </div>

      <div class="step">
        <div class="step-number">2</div>
        <div>
          <h3>Build and Run the App</h3>
          <p>Compile the SwiftUI application and launch it.</p>
        </div>
      </div>

      <div class="step">
        <div class="step-number">3</div>
        <div>
          <h3>Discover and Pair</h3>
          <p>Open the app, discover your Apple TV, and complete the pairing process.</p>
        </div>
      </div>

      <div class="step">
        <div class="step-number">4</div>
        <div>
          <h3>Start Controlling</h3>
          <p>Use the remote control interface to navigate and control your Apple TV.</p>
        </div>
      </div>
    </div>
  </div>
</section>

