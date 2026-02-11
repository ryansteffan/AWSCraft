import { Context, APIGatewayProxyResult, APIGatewayEvent } from "aws-lambda";
import {
	DescribeInstancesCommand,
	EC2Client,
	StartInstancesCommand,
} from "@aws-sdk/client-ec2";

export interface Response {
	success: boolean;
	message: string;
}

export interface POSTRequestBody {
	serverId: string;
}

export const handler = async (
	event: APIGatewayEvent,
	context: Context,
): Promise<APIGatewayProxyResult> => {
	if (event.httpMethod !== "POST") {
		return {
			statusCode: 405,
			body: JSON.stringify({
				success: false,
				message: "Invalid HTTP method. Only POST is allowed.",
			} satisfies Response),
		};
	}

	const requestBody: POSTRequestBody = JSON.parse(
		event.body || "{}",
	) as POSTRequestBody;
	if (!requestBody.serverId || typeof requestBody.serverId !== "string") {
		return {
			statusCode: 400,
			body: JSON.stringify({
				success: false,
				message: "Invalid serverId: It must be a non-empty string.",
			} satisfies Response),
		};
	}

	const ec2Client = new EC2Client({ region: process.env.AWS_REGION });

	try {
		// Check if the instance is a minecraft server.
		const describeCommand = new DescribeInstancesCommand({
			InstanceIds: [requestBody.serverId],
		});

		const describedInstances = await ec2Client.send(describeCommand);

		const instance = describedInstances.Reservations?.[0]?.Instances?.[0];
		if (!instance) {
			return {
				statusCode: 404,
				body: JSON.stringify({
					success: false,
					message:
						"Server not found. Please check the serverId and try again.",
				} satisfies Response),
			};
		}

		const isMinecraftServer = instance.Tags?.find(
			(tag) => tag.Key === "IsMinecraftServer" && tag.Value === "true",
		)?.Value;

		if (isMinecraftServer !== "true") {
			return {
				statusCode: 400,
				body: JSON.stringify({
					success: false,
					message: "The specified server is not a Minecraft server.",
				} satisfies Response),
			};
		}

		// Start the instance.
		const command = new StartInstancesCommand({
			InstanceIds: [requestBody.serverId],
		});

		const response = await ec2Client.send(command);
		console.log("EC2 instance start response:", response);

		return {
			statusCode: 200,
			body: JSON.stringify({
				success: true,
				message:
					"Server is starting. It may take a few moments to be fully operational.",
			} satisfies Response),
		};
	} catch (error) {
		console.error("Error starting EC2 instance:", error);
		return {
			statusCode: 500,
			body: JSON.stringify({
				success: false,
				message: "Failed to start the server. Please try again later.",
			} satisfies Response),
		};
	}
};
