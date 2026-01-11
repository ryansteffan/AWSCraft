import { Context, APIGatewayProxyResult, APIGatewayEvent } from "aws-lambda";

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
	context: Context
): Promise<APIGatewayProxyResult> => {
	console.log(`Event: ${JSON.stringify(event, null, 2)}`);
	console.log(`Context: ${JSON.stringify(context, null, 2)}`);
	return {
		statusCode: 200,
		body: JSON.stringify({
			message: "hello world",
		}),
	};
};
