export const owlracleMock = {
  timestamp: '2022-03-31T00:34:45.035Z',
  baseFee: 62.272509908983146,
  lastBlock: 12792437,
  avgTime: 2,
  avgTx: 19.135,
  avgGas: 203940.40997114248,
  speeds: [
    {
      acceptance: 0.35,
      gasPrice: 62.704668412,
      estimatedFee: 1.23519444448459,
    },
    {
      acceptance: 0.6,
      gasPrice: 63.384299915,
      estimatedFee: 1.248582236463435,
    },
    {
      acceptance: 0.9,
      gasPrice: 65.324311206,
      estimatedFee: 1.2867977510266537,
    },
    { acceptance: 1, gasPrice: 67.930108231, estimatedFee: 1.3381283152453538 },
  ],
};

export const debankMock = {
  _seconds: 0.0004506111145019531,
  data: {
    fast: { estimated_seconds: 0, front_tx_count: 0, price: 64000000000.0 },
    normal: { estimated_seconds: 0, front_tx_count: 0, price: 63000000000.0 },
    slow: { estimated_seconds: 0, front_tx_count: 0, price: 62000000000.0 },
  },
  error_code: 0,
};

export const owlracleApiError = {
  status: 401,
  error: 'Unauthorized',
  message: 'Could not find your api key.',
};
