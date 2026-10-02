import {
	bytesToHex,
	cre,
	getNetwork,
	TxStatus,
	prepareReportRequest,
	type Runtime,
} from '@chainlink/cre-sdk'
import {
	type Address,
	encodeAbiParameters,
	parseAbiParameters,
	encodeFunctionData,
	createPublicClient,
	http,
} from 'viem'
import { z } from 'zod'

// ─── Config Schema ──────────────────────────────────────────
export const configSchema = z.object({
	schedule: z.string(),
	evms: z.array(
		z.object({
			chainSelectorName: z.string(),
			contractAddress: z.string(), // CREBridge address
			registryAddress: z.string(), // PolicyRegistry address
		}),
	),
})
type Config = z.infer<typeof configSchema>

const registryAbi = [
	{
		inputs: [],
		name: 'nextPolicyId',
		outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
		stateMutability: 'view',
		type: 'function',
	},
] as const

// ─── Callback ───────────────────────────────────────────────
export const onCronTrigger = async (runtime: Runtime<Config>): Promise<string> => {
	const evmConfig = runtime.config.evms[0]

	// 1. Get network and create EVM client
	const network = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: evmConfig.chainSelectorName,
		isTestnet: true,
	})
	if (!network) throw new Error(`Network not found: ${evmConfig.chainSelectorName}`)

	const evmClient = new cre.capabilities.EVMClient(network.chainSelector.selector)

	// 2. Query the PolicyRegistry for nextPolicyId using standard viem
	const publicClient = createPublicClient({
		transport: http('https://monad-testnet.g.alchemy.com/v2/OOIMS_hWS2oBIZXbMyjTG'),
	})

	const nextPolicyId = await publicClient.readContract({
		address: evmConfig.registryAddress as Address,
		abi: registryAbi,
		functionName: 'nextPolicyId',
	})

	// 3. Conditional: Only write if there are policies
	if (nextPolicyId === 0n) {
		runtime.log('No policies exist. Skipping execution.')
		return 'Skipped — no policies'
	}

	const policyIds = Array.from({ length: Number(nextPolicyId) }, (_, i) => BigInt(i))
	runtime.log(`Checking health factors for policies: ${policyIds.join(', ')}`)

	// 4. Write: Send execution signal via signed report
	const reportData = encodeAbiParameters(parseAbiParameters('uint256[] policyIds'), [policyIds])

	const callData = encodeFunctionData({
		abi: [
			{
				type: 'function',
				name: 'onReport',
				inputs: [
					{ name: 'metadata', type: 'bytes', internalType: 'bytes' },
					{ name: 'report', type: 'bytes', internalType: 'bytes' },
				],
				outputs: [],
				stateMutability: 'nonpayable',
			},
		] as const,
		functionName: 'onReport',
		args: ['0x', reportData],
	})

	const reportResponse = runtime.report(prepareReportRequest(callData)).result()

	const writeResult = evmClient
		.writeReport(runtime, {
			receiver: evmConfig.contractAddress as Address,
			report: reportResponse,
		})
		.result()

	if (writeResult.txStatus !== TxStatus.SUCCESS) {
		throw new Error(`Keeper TX failed: ${writeResult.errorMessage || writeResult.txStatus}`)
	}

	if (
		writeResult.receiverContractExecutionStatus !== undefined &&
		writeResult.receiverContractExecutionStatus !== 0
	) {
		throw new Error(
			`Receiver contract execution failed: status ${writeResult.receiverContractExecutionStatus}`
		)
	}

	const txHash = bytesToHex(writeResult.txHash || new Uint8Array(32))
	runtime.log(`CRE poll executed! TX: ${txHash}`)

	return `Executed — tx: ${txHash}`
}

// ─── Workflow Init ──────────────────────────────────────────
export function initWorkflow(config: Config) {
	const cronTrigger = new cre.capabilities.CronCapability()

	return [
		cre.handler(cronTrigger.trigger({ schedule: config.schedule }), onCronTrigger),
	]
}
