import { Context, APIGatewayProxyResult, APIGatewayEvent } from "aws-lambda";
import { DescribeInstancesCommand, EC2Client } from "@aws-sdk/client-ec2";

interface Instance {
	instanceId: string;
	name: string;
	description: string;
}

interface Response {
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

	// TODO: Remove debug log
	console.log(process.env.AWS_REGION);

	const ec2Client = new EC2Client({
		region: process.env.AWS_REGION || "us-east-1",
	});

	// List only the instances that have the tag "minecraft" set to "true"
	const command = new DescribeInstancesCommand({
		// Filters: [
		// 	{
		// 		Name: "tag:minecraft",
		// 		Values: ["true"],
		// 	},
		// ],
	});
	const response = await ec2Client.send(command);

	const instances: Instance[] = [];
	response.Reservations?.forEach((reservation) => {
		// TODO: Extract Name and Description from tags
		reservation.Instances?.forEach((instance) => {
			return {
				instanceId: instance.InstanceId || "Unknown",
				name: "",
				description: "",
			} satisfies Instance;
		});
	});

	return {
		statusCode: 200,
		body: JSON.stringify({
			success: true,
			message: "Instances retrieved successfully",
			instances: instances,
		} satisfies Response),
	};
};
