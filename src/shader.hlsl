// cbuffer ConstantBuffer : register(b0) {
//     matrix viewProjection;
// }

struct VS_INPUT {
    float2 position : POSITION;
    float4 color : COLOR;
};

struct PS_INPUT {
    float4 position : SV_POSITION;
    float4 color : COLOR;
};

PS_INPUT vs_main(VS_INPUT input) {
    PS_INPUT output;
    //output.position = mul(float4(input.position, 0.0, 1.0), viewProjection);
    output.position = float4(input.position, 0.0, 1.0);
    output.color = input.color;
    return output;
}

float4 ps_main(PS_INPUT input) : SV_TARGET {
    return input.color;
}
