globalThis.SOUND_LAB_MUSIC = {
  "schemaVersion": 1,
  "tracks": [
    {
      "id": "classic-sunlit-sleeves",
      "mode": "classic",
      "title": "Sunlit Sleeves",
      "description": "Recommended Classic: a conversational felt-key hook, softly strummed nylon, rounded bass and pocket-sized brushes. Warm major-nine voicings open into a gentle answering phrase, then return with a new ending.",
      "bpm": 86.000956,
      "duration": 44.650666666666666,
      "file": "music/classic-sunlit-sleeves.m4a",
      "sha256": "0556584880a7a2d3b3a72252df3398bb5b2747a71aa9d1e69c99d7c29a7877c8",
      "recommended": true,
      "license": "Original composition; no third-party musical content"
    },
    {
      "id": "classic-paper-lanterns",
      "mode": "classic",
      "title": "Paper Lanterns",
      "description": "Classic alternate: a finger-picked nylon melody with little felt-key replies, unhurried brushed percussion and a warm walking answer in the bass. More intimate and acoustic than Sunlit Sleeves.",
      "bpm": 82.004556,
      "duration": 46.82666666666667,
      "file": "music/classic-paper-lanterns.m4a",
      "sha256": "3c38c18ddc300ec177e1dd9f2e67fbde7ae47547ff3fbace418862bc7b1fa32a",
      "recommended": false,
      "license": "Original composition; no third-party musical content"
    },
    {
      "id": "gauntlet-quiet-resolve",
      "mode": "gauntlet",
      "title": "Quiet Resolve",
      "description": "Recommended Gauntlet: a rounded wooden-mallet hook over muted keys, a gently moving bass line and quiet cloth-and-rim percussion. Descending bass harmony and an open second phrase give momentum without urgency.",
      "bpm": 106.007067,
      "duration": 36.224,
      "file": "music/gauntlet-quiet-resolve.m4a",
      "sha256": "cbe59c703cb6cf58245bcc894d6189b49e50f6de841921257eeb80ebdb25f576",
      "recommended": true,
      "license": "Original composition; no third-party musical content"
    },
    {
      "id": "gauntlet-northbound",
      "mode": "gauntlet",
      "title": "Northbound",
      "description": "Gauntlet alternate: a soft, syncopated nylon hook, broad felt-key responses and a half-time brushed pocket. A little more spacious and reflective, with a subtly busier bass in the second half.",
      "bpm": 101.983003,
      "duration": 37.653333333333336,
      "file": "music/gauntlet-northbound.m4a",
      "sha256": "7cc82d2b8003e79fc52fece3b67b5b2143c0702febc0774fd3cf629d17d5dbba",
      "recommended": false,
      "license": "Original composition; no third-party musical content"
    }
  ],
  "render": {
    "sourceSha256": {
      "tools/generate_music.py": "1565093ba6e1d1be0ced8b40ba397cd2e17d7c795634757ac7e3bc99375cbac2",
      "tools/sound_lab/music.py": "f606f299d2c690d0523340d3206cb74885db8190a13dc3888eac57c1ec61f313",
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
        "frames": 2143232,
        "nominalBPM": 86,
        "events": 481,
        "wrappedEvents": 16,
        "pcmSha256": "1f41cdaee294b823c4ff897fa95e3159a09026dc97cac4c124533c99cd0808c0",
        "pcm": {
          "frames": 2143232,
          "peakDBFS": -9.607852,
          "rmsDBFS": -23.0,
          "boundaryStep": 0.0012226160615682602,
          "nearbyStepP99": 0.023481816053390503,
          "edgeRMSRatio": 0.46999746230064054,
          "dc": 2.5030522758535107e-12
        },
        "decoded": {
          "frames": 2143232,
          "peakDBFS": -9.606693,
          "rmsDBFS": -23.009735,
          "boundaryStep": 0.00100787915289402,
          "nearbyStepP99": 0.023225446231663227,
          "edgeRMSRatio": 0.46906036414104113,
          "dc": 3.262640022479168e-06,
          "integratedLUFS": -20.8,
          "truePeakDBFS": -9.6,
          "primingFrames": 1024,
          "paddingFrames": 0,
          "bytes": 1086172
        }
      },
      "classic-paper-lanterns": {
        "bars": 16,
        "frames": 2247680,
        "nominalBPM": 82,
        "events": 475,
        "wrappedEvents": 17,
        "pcmSha256": "d615fbde441e951067307acd08df1ba1485d567bef224395b98597557ee05b11",
        "pcm": {
          "frames": 2247680,
          "peakDBFS": -8.499957,
          "rmsDBFS": -25.128967,
          "boundaryStep": 0.00024078693240880966,
          "nearbyStepP99": 0.004276275634765625,
          "edgeRMSRatio": 0.3984682694789031,
          "dc": 1.0438068650055759e-12
        },
        "decoded": {
          "frames": 2247680,
          "peakDBFS": -8.523535,
          "rmsDBFS": -25.139928,
          "boundaryStep": 0.0003856755793094635,
          "nearbyStepP99": 0.00427694246172905,
          "edgeRMSRatio": 0.3984903858159844,
          "dc": 3.7093589224222534e-06,
          "integratedLUFS": -22.6,
          "truePeakDBFS": -8.5,
          "primingFrames": 1024,
          "paddingFrames": 0,
          "bytes": 1144990
        }
      },
      "gauntlet-quiet-resolve": {
        "bars": 16,
        "frames": 1738752,
        "nominalBPM": 106,
        "events": 612,
        "wrappedEvents": 16,
        "pcmSha256": "f313c2def1a831a626fa3e283ce869e5439828efad7b4f8fd9512fad33c5c22c",
        "pcm": {
          "frames": 1738752,
          "peakDBFS": -8.49995,
          "rmsDBFS": -23.815909,
          "boundaryStep": 0.0006750784814357758,
          "nearbyStepP99": 0.007057309150695801,
          "edgeRMSRatio": 0.5207349741275076,
          "dc": 1.693648088709155e-12
        },
        "decoded": {
          "frames": 1738752,
          "peakDBFS": -8.502839,
          "rmsDBFS": -23.823613,
          "boundaryStep": 0.00080103799700737,
          "nearbyStepP99": 0.007059501484036446,
          "edgeRMSRatio": 0.5211657474651504,
          "dc": 2.063847085751362e-06,
          "integratedLUFS": -22.0,
          "truePeakDBFS": -8.5,
          "primingFrames": 1024,
          "paddingFrames": 0,
          "bytes": 897211
        }
      },
      "gauntlet-northbound": {
        "bars": 16,
        "frames": 1807360,
        "nominalBPM": 102,
        "events": 479,
        "wrappedEvents": 17,
        "pcmSha256": "f4e526103f3acce2716df707e636c340f12296fac8c8b6d95383c15ddbc0dc5d",
        "pcm": {
          "frames": 1807360,
          "peakDBFS": -8.500009,
          "rmsDBFS": -24.37647,
          "boundaryStep": 0.00020481552928686142,
          "nearbyStepP99": 0.005089662969112396,
          "edgeRMSRatio": 0.46180071838588743,
          "dc": 7.636649889727057e-13
        },
        "decoded": {
          "frames": 1807360,
          "peakDBFS": -8.570338,
          "rmsDBFS": -24.388849,
          "boundaryStep": 0.0004811035469174385,
          "nearbyStepP99": 0.005076856352388859,
          "edgeRMSRatio": 0.46186400996478216,
          "dc": 2.8811532275245704e-06,
          "integratedLUFS": -21.8,
          "truePeakDBFS": -8.6,
          "primingFrames": 1024,
          "paddingFrames": 0,
          "bytes": 924635
        }
      }
    }
  }
};
