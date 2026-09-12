package middleware

import (
	"github.com/gin-gonic/gin"
	"rustdesk-api/http/response"
	"rustdesk-api/service"
)

// AdminPrivilege ...
func AdminPrivilege() gin.HandlerFunc {
	return func(c *gin.Context) {
		u := service.AllService.CurUser(c)

		if !service.AllService.IsAdmin(u) {
			response.Fail(c, 403, response.TranslateMsg(c, "NoAccess"))
			c.Abort()
			return
		}

		c.Next()
	}
}
