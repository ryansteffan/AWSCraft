import { Context, APIGatewayProxyResult, APIGatewayEvent } from "aws-lambda";
import { DescribeInstancesCommand, EC2Client } from "@aws-sdk/client-ec2";

export type InstanceStatus =
	| "pending"
	| "running"
	| "shutting-down"
	| "terminated"
	| "stopping"
	| "stopped";

export interface Instance {
	instanceId: string;
	name: string;
	description: string;
	status: InstanceStatus;
	ipAddress: string | undefined;
	publicDNS: string | undefined;
}

export interface Response {
	success: boolean;
	message: string;
	instances: Instance[];
}

export const handler = async (
	event: APIGatewayEvent,
	context: Context,
): Promise<APIGatewayProxyResult> => {
	if (event.httpMethod !== "GET") {
		return {
			statusCode: 405,
			body: JSON.stringify({
				success: false,
				message: "Method Not Allowed",
				instances: [],
			} satisfies Response),
		};
	}

	const instanceID = event.queryStringParameters?.instanceId;
	if (!instanceID) {
		return {
			statusCode: 400,
			body: JSON.stringify({
				success: false,
				message: "Missing instanceId query parameter",
				instances: [],
			} satisfies Response),
		};
	}

	try {
		const ec2Client = new EC2Client({
			region: process.env.AWS_REGION,
		});

		const describeCommand = new DescribeInstancesCommand({
			InstanceIds: [instanceID],
		});

		const describedInstances = await ec2Client.send(describeCommand);

		const instance = describedInstances.Reservations?.[0]?.Instances?.[0];
		if (!instance) {
			return {
				statusCode: 404,
				body: JSON.stringify({
					success: false,
					message: "Instance not found",
					instances: [],
				} satisfies Response),
			};
		}

		return {
			statusCode: 200,
			body: JSON.stringify({
				success: true,
				message: "Successfully retrieved instance status",
				instances: [
					{
						instanceId: instance.InstanceId || "Unknown",
						name:
							instance.Tags?.find((tag) => tag.Key === "Name")
								?.Value || "Unnamed",
						description:
							instance.Tags?.find(
								(tag) => tag.Key === "Description",
							)?.Value || "No description",
						status:
							(instance.State?.Name as InstanceStatus) ||
							"Unknown",
						ipAddress: instance.PublicIpAddress || undefined,
						publicDNS: instance.PublicDnsName || undefined,
					},
				],
			} satisfies Response),
		};
	} catch (error) {
		console.error("Error creating EC2 client:", error);
		return {
			statusCode: 500,
			body: JSON.stringify({
				success: false,
				message: "Error getting server status",
				instances: [],
			} satisfies Response),
		};
	}
};
