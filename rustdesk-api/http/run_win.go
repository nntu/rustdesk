//go:build windows

package http

import (
	"github.com/gin-gonic/gin"
)

func Run(g *gin.Engine, addr string) {
	_ = g.Run(addr)
}
