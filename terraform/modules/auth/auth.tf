# -----------------------------------------------------
# Cognito User Pool for Minecraft Server Authentication
# -----------------------------------------------------

variable "MinecraftAdminUsername" {
  description = "The username for the default admin user in the Minecraft server."
  type        = string
}

variable "MinecraftAdminPassword" {
  description = "The temporary password for the default admin user in the Minecraft server. This should be changed immediately after the first login."
  type        = string
  sensitive   = true
}

# Create a user pool for managing users who have access to the Minecraft server.
resource "aws_cognito_user_pool" "MinecraftUserPool" {
  name = "MinecraftUserPool"
  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_message = "You have been invited to join the Minecraft server! Your username is {username} and your temporary password is {####}. Please log in and change your password as soon as possible."
      email_subject = "Minecraft Server Invitation"
      sms_message   = "You have been invited to join the Minecraft server! Your username is {username} and your temporary password is {####}."
    }
  }
}

# Create a PKCE client for the user pool to allow for mod and webui authentication.
resource "aws_cognito_user_pool_client" "MinecraftPKCEClient" {
  name         = "MinecraftPKCEClient"
  user_pool_id = aws_cognito_user_pool.MinecraftUserPool.id
}

# Create a user group for people that have access to the admin API of the Minecraft server.
resource "aws_cognito_user_group" "MinecraftAdminsGroup" {
  name         = "MinecraftAdminsGroup"
  user_pool_id = aws_cognito_user_pool.MinecraftUserPool.id
}

# Create a user group for people that have access to the player API of the Minecraft server.
resource "aws_cognito_user_group" "MinecraftPlayersGroup" {
  name         = "MinecraftPlayersGroup"
  user_pool_id = aws_cognito_user_pool.MinecraftUserPool.id
}

# Create a default user for the admin group to allow for initial login and setup of the server.
resource "aws_cognito_user" "DefaultAdminUser" {
  username             = var.MinecraftAdminUsername
  user_pool_id         = aws_cognito_user_pool.MinecraftUserPool.id
  temporary_password   = var.MinecraftAdminPassword
  force_alias_creation = false
  lifecycle {
    ignore_changes = [temporary_password]
  }
}

# Add the default admin user to the admin group.
resource "aws_cognito_user_in_group" "DefaultAdminMembership" {
  user_pool_id = aws_cognito_user_pool.MinecraftUserPool.id
  username     = aws_cognito_user.DefaultAdminUser.username
  group_name   = aws_cognito_user_group.MinecraftAdminsGroup.name
}

output "MinecraftUserPoolEndpoint" {
  value = aws_cognito_user_pool.MinecraftUserPool.endpoint
}

output "MinecraftPKCEClientID" {
  value = aws_cognito_user_pool_client.MinecraftPKCEClient.id
}
