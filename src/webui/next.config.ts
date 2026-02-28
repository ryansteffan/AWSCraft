import type { NextConfig } from "next";

const nextConfig: NextConfig = {
	/* config options here */
	output: "export", // Static export of application
	trailingSlash: true, // Remove .html from URLs
};

export default nextConfig;
