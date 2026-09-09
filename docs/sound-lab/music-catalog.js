globalThis.SOUND_LAB_MUSIC = {
  "schemaVersion": 1,
  "tracks": [
    {
      "id": "classic-sunlit-sleeves",
      "mode": "classic",
      "title": "Sunlit Sleeves",
      "description": "Classic alternate / challenger mix: a playful rounded-reed hook, springy bass and soft plucked arpeggios. A friendly turn-based duel rather than a boss fight, with quieter answers and no piercing lead.",
      "bpm": 107.978404,
      "duration": 35.562666666666665,
      "file": "music/classic-sunlit-sleeves.m4a",
      "sha256": "566beca9044c8c4a9ce169b593c5ea80f44b3a4f6294e9210a7e59631c2dff6e",
      "recommended": false,
      "license": "Original composition; no third-party musical content"
    },
    {
      "id": "classic-paper-lanterns",
      "mode": "classic",
      "title": "Paper Lanterns",
      "description": "Selected Classic / tactical mix: a warm wooden-mallet question and answer, nimble bass and little nylon figures. Minor-key curiosity with a lighter, more spacious rhythm for long collecting sessions.",
      "bpm": 103.986135,
      "duration": 36.928,
      "file": "music/classic-paper-lanterns.m4a",
      "sha256": "267acb0d1757bc7584c7f55893b5e9be728e5e73c338e60ec7f45d2f1456a913",
      "recommended": true,
      "license": "Original composition; no third-party musical content"
    },
    {
      "id": "gauntlet-quiet-resolve",
      "mode": "gauntlet",
      "title": "Quiet Resolve",
      "description": "Selected Gauntlet / battle mix: a soft-brass challenger motif, a pulsing B-minor bass line and quick plucked replies. Brief tom fills and dominant-chord turns add resolve; quieter phrases keep it repeat-friendly.",
      "bpm": 120.0,
      "duration": 32.0,
      "file": "music/gauntlet-quiet-resolve.m4a",
      "sha256": "4bef58b88ecbd63d5d5e0c1a3ed1dc684f931b80baab4e234c2554f4c736e8ee",
      "recommended": true,
      "license": "Original composition; no third-party musical content"
    },
    {
      "id": "gauntlet-northbound",
      "mode": "gauntlet",
      "title": "Northbound",
      "description": "Gauntlet alternate / scout mix: a nimble nylon hook over a walking minor-key pulse, warm reed answers and a half-time drum pocket. Forward-looking challenge energy with more space than the battle mix.",
      "bpm": 115.979381,
      "duration": 33.10933333333333,
      "file": "music/gauntlet-northbound.m4a",
      "sha256": "d1be4a05f17c14d6a235327cf94b065981bfcee7512949bae5dd17c430db1846",
      "recommended": false,
      "license": "Original composition; no third-party musical content"
    }
  ],
  "render": {
    "sourceSha256": {
      "tools/generate_music.py": "94bb84a231e66cde75a1f8e1e6e725a943f076da1210b09e341112da4665725b",
      "tools/sound_lab/music.py": "ea5a7a6cfdc87344bcc595282faff43a85274c5e08d088f5d7704816ae3c4da0",
      "tools/sound_lab/dsp.py": "77cb0525b52cabd6f15a7202c093a7134a2a07ddeb00bb8b7dd4e645c71fbcf2"
    },
    "sampleRate": 48000,
    "channels": 2,
    "codec": "AAC-LC",
    "bitrate": 192000,
    "aacAccessUnitFrames": 1024,
    "encoder": "ffmpeg version 9.0.1 Copyright (c) 2000-2026 the FFmpeg developers",
    "loopMethod": "periodic wrap-add; two-period room warm-up; middle-of-three AAC encode with edit-list pre-roll",
    "tracks": {
      "classic-sunlit-sleeves": {
        "bars": 16,
        "frames": 1707008,
        "nominalBPM": 108,
        "events": 550,
        "wrappedEvents": 14,
        "pcmSha256": "7fb9cf557e5c04505302d97d61aa47bc6b441923dfeaca4caaf4a6296062b223",
        "pcm": {
          "frames": 1707008,
          "peakDBFS": -9.045325,
          "rmsDBFS": -24.0,
          "boundaryStep": 0.00044055841863155365,
          "nearbyStepP99": 0.02903250977396965,
          "edgeRMSRatio": 0.2766292861659973,
          "dc": 2.2784097727200504e-12
        },
        "decoded": {
          "frames": 1707008,
          "peakDBFS": -9.033782,
          "rmsDBFS": -24.010464,
          "boundaryStep": 0.0007009441033005714,
          "nearbyStepP99": 0.02866574178915471,
          "edgeRMSRatio": 0.27638341943517525,
          "dc": 5.950289166600142e-06,
          "integratedLUFS": -21.8,
          "truePeakDBFS": -9.0,
          "primingFrames": 1024,
          "paddingFrames": 0,
          "bytes": 862372
        }
      },
      "classic-paper-lanterns": {
        "bars": 16,
        "frames": 1772544,
        "nominalBPM": 104,
        "events": 508,
        "wrappedEvents": 12,
        "pcmSha256": "5efb3772a1ecc98890c95d6f61139cba088ad35e6b3fa2174000ee3ff0e17402",
        "pcm": {
          "frames": 1772544,
          "peakDBFS": -8.907793,
          "rmsDBFS": -24.0,
          "boundaryStep": 0.00031162798404693604,
          "nearbyStepP99": 0.006443750113248825,
          "edgeRMSRatio": 0.2843073046527327,
          "dc": 5.428779121512173e-13
        },
        "decoded": {
          "frames": 1772544,
          "peakDBFS": -8.930758,
          "rmsDBFS": -24.00793,
          "boundaryStep": 0.0008518341928720474,
          "nearbyStepP99": 0.0064113326370716095,
          "edgeRMSRatio": 0.2839549371617494,
          "dc": 1.8080532017656922e-06,
          "integratedLUFS": -22.0,
          "truePeakDBFS": -8.9,
          "primingFrames": 1024,
          "paddingFrames": 0,
          "bytes": 907214
        }
      },
      "gauntlet-quiet-resolve": {
        "bars": 16,
        "frames": 1536000,
        "nominalBPM": 120,
        "events": 555,
        "wrappedEvents": 12,
        "pcmSha256": "83a5cc2a187024a948368270c8a2e748a22aff56869921fb3b8528c7ec93e577",
        "pcm": {
          "frames": 1536000,
          "peakDBFS": -8.796699,
          "rmsDBFS": -24.0,
          "boundaryStep": 5.894548667129129e-05,
          "nearbyStepP99": 0.0145193412899971,
          "edgeRMSRatio": 0.2803827709972082,
          "dc": 2.149829748827418e-12
        },
        "decoded": {
          "frames": 1536000,
          "peakDBFS": -8.789027,
          "rmsDBFS": -24.005954,
          "boundaryStep": 4.504778189584613e-05,
          "nearbyStepP99": 0.01451798528432846,
          "edgeRMSRatio": 0.28069556314045707,
          "dc": 9.32162885947879e-07,
          "integratedLUFS": -22.0,
          "truePeakDBFS": -8.8,
          "primingFrames": 1024,
          "paddingFrames": 0,
          "bytes": 787485
        }
      },
      "gauntlet-northbound": {
        "bars": 16,
        "frames": 1589248,
        "nominalBPM": 116,
        "events": 522,
        "wrappedEvents": 14,
        "pcmSha256": "7a18cccace260b3593443538a2e693044fc727bcb195d19563364cc9a27e5e77",
        "pcm": {
          "frames": 1589248,
          "peakDBFS": -8.500025,
          "rmsDBFS": -25.634906,
          "boundaryStep": 0.0077713485807180405,
          "nearbyStepP99": 0.043990712612867355,
          "edgeRMSRatio": 0.3212444728659039,
          "dc": 1.2778870230567613e-12
        },
        "decoded": {
          "frames": 1589248,
          "peakDBFS": -8.54237,
          "rmsDBFS": -25.647802,
          "boundaryStep": 0.00809796154499054,
          "nearbyStepP99": 0.04346857080236077,
          "edgeRMSRatio": 0.32101545877678217,
          "dc": 8.323786328248853e-07,
          "integratedLUFS": -22.8,
          "truePeakDBFS": -8.5,
          "primingFrames": 1024,
          "paddingFrames": 0,
          "bytes": 811337
        }
      }
    }
  }
};
