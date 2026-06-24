import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async redirects() {
    return [
      {
        source: "/",
        destination: "https://nima.so",
        permanent: true,
      },
      {
        source: "/login",
        destination: "https://nima.so",
        permanent: true,
      },
      {
        source: "/dashboard/:path*",
        destination: "https://nima.so",
        permanent: true,
      },
    ];
  },
};

export default nextConfig;
