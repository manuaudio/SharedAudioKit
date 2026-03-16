//
//  MeterShaders.metal
//  MeterKit
//
//  GPU-accelerated meter rendering using Metal
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct MeterUniforms {
    float level;          // Current RMS level (0.0-1.0)
    float peak;           // Peak level (0.0-1.0)
    float peakHold;       // Peak hold level (0.0-1.0)
    float meterHeight;    // Height in pixels
    float kScale;         // K-system scale (12, 14, or 20)
};

// Vertex shader
vertex VertexOut meter_vertex(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

// Convert dB to linear (0.0-1.0 range)
float dbToLinear(float db) {
    return pow(10.0, db / 20.0);
}

// K-System color for a specific dB level
// Based on K-20 standard with proper color zones
float3 kSystemColorForDB(float db, float kScale) {
    // K-20 zones (referenced to 0 dBFS):
    // Green: below -24 dB
    // Yellow: -24 to -18 dB (starts yellow, transitioning)
    // Orange: -18 to -10 dB (yellow to orange transition)
    // Red: -10 dB and above

    float yellowStart = -24.0;   // Start yellowing
    float orangeStart = -18.0;   // Fully yellow, start orange transition
    float redStart = -10.0;      // Fully orange, start red transition

    if (db < yellowStart) {
        // Green zone - safe levels
        // Bright green, gets darker as level decreases
        float brightness = clamp((db - (-60.0)) / (yellowStart - (-60.0)), 0.3, 1.0);
        return float3(0.0, 0.8 * brightness, 0.0);
    } else if (db < orangeStart) {
        // Green to Yellow transition (-24 to -18 dB)
        float t = (db - yellowStart) / (orangeStart - yellowStart);
        return mix(float3(0.0, 0.8, 0.0), float3(1.0, 1.0, 0.0), t);
    } else if (db < redStart) {
        // Yellow to Orange transition (-18 to -10 dB)
        float t = (db - orangeStart) / (redStart - orangeStart);
        return mix(float3(1.0, 1.0, 0.0), float3(1.0, 0.5, 0.0), t);
    } else {
        // Orange to Red transition (-10 dB to 0 dBFS)
        float t = clamp((db - redStart) / (0.0 - redStart), 0.0, 1.0);
        return mix(float3(1.0, 0.5, 0.0), float3(1.0, 0.0, 0.0), t);
    }
}

// Fragment shader for vertical meter
fragment float4 meter_fragment(
    VertexOut in [[stage_in]],
    constant MeterUniforms &uniforms [[buffer(0)]]
) {
    float2 uv = in.texCoord;

    // Vertical meter: 0 at bottom, 1 at top
    float normY = uv.y;

    // Background color (dark gray)
    float3 color = float3(0.1, 0.1, 0.12);
    float alpha = 1.0;

    // Draw RMS level bar
    if (normY < uniforms.level) {
        // Convert this Y position to dB
        // normY ranges from 0 (bottom, -60 dB) to 1 (top, 0 dB)
        float positionDB = (normY * 60.0) - 60.0;  // -60 to 0 dB

        // Get color for this dB level using K-System
        color = kSystemColorForDB(positionDB, uniforms.kScale);

        // Add subtle glow at the top of the level
        float glowDist = abs(normY - uniforms.level);
        if (glowDist < 0.02) {
            float glowIntensity = (1.0 - (glowDist / 0.02)) * 0.3;
            color += float3(glowIntensity);
        }
    }

    // Draw peak indicator (thin bright line)
    if (abs(normY - uniforms.peak) < 0.003) {
        color = float3(1.0, 1.0, 0.0);  // Bright yellow peak
    }

    // Draw peak hold (bright line that pulses)
    if (abs(normY - uniforms.peakHold) < 0.004) {
        color = float3(1.0, 0.2, 0.0);  // Bright red-orange
    }

    // Add dB scale markers every 10 dB (on left side)
    if (uv.x < 0.15) {
        // Markers at -50, -40, -30, -20, -10, 0 dB
        float dbMarkers[] = {-50.0, -40.0, -30.0, -20.0, -10.0, 0.0};
        for (int i = 0; i < 6; i++) {
            float markerY = (dbMarkers[i] + 60.0) / 60.0;  // Convert dB to 0-1
            if (abs(normY - markerY) < 0.002) {
                color = float3(0.5, 0.5, 0.5);
            }
        }
    }

    return float4(color, alpha);
}

// Fragment shader for peak indicator light
fragment float4 peak_light_fragment(
    VertexOut in [[stage_in]],
    constant MeterUniforms &uniforms [[buffer(0)]]
) {
    float2 uv = in.texCoord;

    // Circular gradient for peak light
    float2 center = float2(0.5, 0.5);
    float dist = length(uv - center);

    float3 color;
    float alpha;

    if (uniforms.peak > 0.99) {
        // Clipping - bright red with pulsing
        float pulse = sin(uniforms.peak * 100.0) * 0.3 + 0.7;
        color = float3(1.0, 0.0, 0.0) * pulse;
        alpha = (1.0 - dist) * pulse;
    } else if (uniforms.peak > 0.95) {
        // Near clip - orange
        color = float3(1.0, 0.5, 0.0);
        alpha = (1.0 - dist) * 0.8;
    } else if (uniforms.peak > 0.7) {
        // Yellow
        color = float3(1.0, 1.0, 0.0);
        alpha = (1.0 - dist) * 0.6;
    } else {
        // Green
        color = float3(0.0, 0.8, 0.0);
        alpha = (1.0 - dist) * 0.4;
    }

    // Smooth edges
    alpha *= smoothstep(0.5, 0.0, dist);

    return float4(color, alpha);
}
